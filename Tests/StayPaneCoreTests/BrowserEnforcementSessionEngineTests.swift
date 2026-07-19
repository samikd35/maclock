import Foundation
import Testing
@testable import StayPaneCore

@MainActor
@Test func disconnectedBrowserEnforcementPreflightRefusesSessionStart() throws {
    let browser = BrowserTestEnforcement(preflightError: .disconnected)
    let engine = SessionEngine(
        clock: TabTargetTestClock(),
        enforcement: ApplicationAndWindowTestEnforcement(),
        browserEnforcement: browser
    )
    engine.beginConfiguration(duration: SessionDuration(seconds: 60)!)
    let tab = makeBrowserTabTarget()
    engine.select(target: .browserTab(tab))

    #expect(throws: BrowserTestError.disconnected) {
        try engine.beginStartCountdown()
    }

    guard case let .ready(draft) = engine.state else {
        Issue.record("Failed browser preflight must leave the Session editable.")
        return
    }
    #expect(draft.targets == [.browserTab(tab)])
    #expect(browser.preflightTargets == [.tab(tab)])
}

@MainActor
@Test func tabTargetSessionCoordinatesBothEnforcementAdaptersUntilCompletion() throws {
    let clock = TabTargetTestClock()
    let native = ApplicationAndWindowTestEnforcement()
    let browser = BrowserTestEnforcement()
    let engine = SessionEngine(
        clock: clock,
        enforcement: native,
        browserEnforcement: browser
    )
    engine.beginConfiguration(duration: SessionDuration(seconds: 60)!)
    let tab = makeBrowserTabTarget()
    engine.select(target: .browserTab(tab))
    try engine.beginStartCountdown(seconds: 0)

    try engine.advance()

    #expect(native.startedTargets == [.application(tab.application)])
    #expect(browser.startedTargets == [.tab(tab)])
    clock.advance(by: 60)

    try engine.advance()

    guard case .completed = engine.state else {
        Issue.record("The coordinated Session should complete normally.")
        return
    }
    #expect(native.stopCount == 1)
    #expect(browser.stopCount == 1)
}

@MainActor
@Test func browserWindowSessionCoordinatesBroadBrowserAndNativeEnforcement() throws {
    let clock = TabTargetTestClock()
    let native = ApplicationAndWindowTestEnforcement()
    let browser = BrowserTestEnforcement()
    let engine = SessionEngine(
        clock: clock,
        enforcement: native,
        browserEnforcement: browser
    )
    let chrome = ApplicationTarget(
        displayName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome"
    )
    let window = BrowserWindowTarget(
        profileIdentifier: BrowserProfileIdentifier(rawValue: "profile-one"),
        windowIdentifier: BrowserWindowIdentifier(rawValue: 9),
        application: chrome
    )
    engine.beginConfiguration(duration: SessionDuration(seconds: 60)!)
    engine.select(target: .browserWindow(window))
    try engine.beginStartCountdown(seconds: 0)

    try engine.advance()

    #expect(native.startedTargets == [.application(chrome)])
    #expect(browser.startedTargets == [.window(window)])
    clock.advance(by: 60)

    try engine.advance()

    guard case .completed = engine.state else {
        Issue.record("The broad browser window Session should complete normally.")
        return
    }
    #expect(native.stopCount == 1)
    #expect(browser.stopCount == 1)
}

@MainActor
@Test func extensionFailureDuringStartReturnsToReadyBeforeNativeEnforcement() throws {
    let clock = TabTargetTestClock()
    let native = ApplicationAndWindowTestEnforcement()
    let browserEnforcement = BrowserTestEnforcement()
    browserEnforcement.startResult = .awaitingConfirmation
    let engine = SessionEngine(
        clock: clock,
        enforcement: native,
        browserEnforcement: browserEnforcement
    )
    engine.beginConfiguration(duration: SessionDuration(seconds: 60)!)
    let tab = makeBrowserTabTarget()
    engine.select(target: .browserTab(tab))
    try engine.beginStartCountdown(seconds: 0)

    try engine.advance()
    guard case .starting = engine.state else {
        Issue.record("The Session must wait for extension confirmation.")
        return
    }
    #expect(native.startedTargets.isEmpty)

    browserEnforcement.startError = .disconnected
    #expect(throws: BrowserTestError.disconnected) {
        try engine.advance()
    }
    guard case let .ready(draft) = engine.state else {
        Issue.record("A failed extension start must return to Ready.")
        return
    }
    #expect(draft.targets == [.browserTab(tab)])
    #expect(native.startedTargets.isEmpty)
}

@MainActor
@Test func lostBridgeConnectionCanFailOpenAnActiveTabTargetSession() throws {
    let clock = TabTargetTestClock()
    let native = ApplicationAndWindowTestEnforcement()
    let browser = BrowserTestEnforcement()
    let engine = SessionEngine(
        clock: clock,
        enforcement: native,
        browserEnforcement: browser
    )
    engine.beginConfiguration(duration: SessionDuration(seconds: 60)!)
    engine.select(target: .browserTab(makeBrowserTabTarget()))
    try engine.beginStartCountdown(seconds: 0)
    try engine.advance()
    browser.refreshError = .disconnected

    #expect(throws: BrowserTestError.disconnected) {
        try engine.advance()
    }
    try engine.interrupt(reason: .enforcementUnavailable)

    guard case .interrupted = engine.state else {
        Issue.record("A lost Bridge Connection must support Fail Open.")
        return
    }
    #expect(native.stopCount == 1)
    #expect(browser.stopCount == 1)
}

@MainActor
@Test func recoveryResumesBothSidesOfATabSession() throws {
    let clock = TabTargetTestClock()
    let tab = makeBrowserTabTarget()
    let recovery = TabTargetTestRecoveryStore(
        snapshot: SessionRecoverySnapshot(
            plan: SessionPlan(
                duration: SessionDuration(seconds: 60)!,
                targets: [.browserTab(tab)],
                preparedAt: clock.now
            ),
            startedAt: clock.now,
            endsAt: clock.now.addingTimeInterval(60),
            phase: .enforcing
        )
    )
    let native = ApplicationAndWindowTestEnforcement()
    let browser = BrowserTestEnforcement()
    browser.startResult = .awaitingConfirmation
    let engine = SessionEngine(
        clock: clock,
        enforcement: native,
        browserEnforcement: browser,
        recoveryStore: recovery
    )

    #expect(try engine.recover() == .awaitingEnforcement)
    guard case .recovering = engine.state else {
        Issue.record("Recovery must wait for the extension confirmation.")
        return
    }
    #expect(engine.state.requiresControlledQuit)
    #expect(native.startedTargets.isEmpty)

    browser.startResult = .active
    try engine.advance()

    guard case .enforcing = engine.state else {
        Issue.record("Recovery must resume after exact tab confirmation.")
        return
    }
    #expect(native.startedTargets == [.application(tab.application)])
    #expect(browser.startedTargets == [.tab(tab)])
}

@MainActor
@Test func failedExtensionConfirmationInterruptsPendingRecovery() throws {
    let clock = TabTargetTestClock()
    let tab = makeBrowserTabTarget()
    let recovery = makeRecoveryStore(clock: clock, tab: tab)
    let native = ApplicationAndWindowTestEnforcement()
    let browser = BrowserTestEnforcement()
    browser.startResult = .awaitingConfirmation
    let engine = SessionEngine(
        clock: clock,
        enforcement: native,
        browserEnforcement: browser,
        recoveryStore: recovery
    )

    #expect(try engine.recover() == .awaitingEnforcement)
    browser.startError = .disconnected

    #expect(throws: BrowserTestError.disconnected) {
        try engine.advance()
    }
    guard case let .interrupted(interruptedSession) = engine.state else {
        Issue.record("Failed recovery confirmation must Fail Open.")
        return
    }
    #expect(interruptedSession.reason == .recoveryUnavailable)
    #expect(try recovery.load() == nil)
    #expect(native.startedTargets.isEmpty)
}

@MainActor
@Test func timerCompletionWinsWhileRecoveryAwaitsExtensionConfirmation() throws {
    let clock = TabTargetTestClock()
    let tab = makeBrowserTabTarget()
    let recovery = makeRecoveryStore(clock: clock, tab: tab)
    let native = ApplicationAndWindowTestEnforcement()
    let browser = BrowserTestEnforcement()
    browser.startResult = .awaitingConfirmation
    let engine = SessionEngine(
        clock: clock,
        enforcement: native,
        browserEnforcement: browser,
        recoveryStore: recovery
    )

    #expect(try engine.recover() == .awaitingEnforcement)
    clock.advance(by: 60)
    try engine.advance()

    guard case .completed = engine.state else {
        Issue.record("The Fixed End Time must complete pending recovery.")
        return
    }
    #expect(try recovery.load() == nil)
    #expect(native.startedTargets.isEmpty)
}

@MainActor
private func makeRecoveryStore(
    clock: TabTargetTestClock,
    tab: BrowserTabTarget
) -> TabTargetTestRecoveryStore {
    TabTargetTestRecoveryStore(
        snapshot: SessionRecoverySnapshot(
            plan: SessionPlan(
                duration: SessionDuration(seconds: 60)!,
                targets: [.browserTab(tab)],
                preparedAt: clock.now
            ),
            startedAt: clock.now,
            endsAt: clock.now.addingTimeInterval(60),
            phase: .enforcing
        )
    )
}

private func makeBrowserTabTarget(
    tabID: Int = 41
) -> BrowserTabTarget {
    BrowserTabTarget(
        profileIdentifier: BrowserProfileIdentifier(rawValue: "profile-one"),
        tabIdentifier: BrowserTabIdentifier(rawValue: tabID),
        windowIdentifier: BrowserWindowIdentifier(rawValue: 9),
        title: "Project plan",
        url: URL(string: "https://work.example/project")!,
        faviconPNGData: nil,
        application: ApplicationTarget(
            displayName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome"
        )
    )
}

@MainActor
private final class TabTargetTestClock: SessionClock {
    var now = Date(timeIntervalSince1970: 80_000)
    var continuousNow: TimeInterval = 200

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        continuousNow += seconds
    }
}

@MainActor
private final class ApplicationAndWindowTestEnforcement: SessionEnforcing {
    private(set) var startedTargets: [SessionTarget] = []
    private(set) var stopCount = 0

    func start(allowing targets: [SessionTarget]) throws {
        startedTargets = targets
    }
    func refresh() throws {}
    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class BrowserTestEnforcement: BrowserEnforcing {
    private let preflightError: BrowserTestError?
    private(set) var preflightTargets: [BrowserEnforcementTarget] = []
    private(set) var startedTargets: [BrowserEnforcementTarget] = []
    private(set) var stopCount = 0
    var refreshError: BrowserTestError?
    var startError: BrowserTestError?
    var startResult: BrowserEnforcementStartResult = .active

    init(preflightError: BrowserTestError? = nil) {
        self.preflightError = preflightError
    }

    func preflight(targets: [BrowserEnforcementTarget]) throws {
        preflightTargets = targets
        if let preflightError {
            throw preflightError
        }
    }

    func start(
        allowing targets: [BrowserEnforcementTarget]
    ) throws -> BrowserEnforcementStartResult {
        if let startError {
            throw startError
        }
        startedTargets = targets
        return startResult
    }
    func refresh() throws {
        if let refreshError {
            throw refreshError
        }
    }
    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class TabTargetTestRecoveryStore: SessionRecoveryPersisting {
    private var snapshot: SessionRecoverySnapshot?

    init(snapshot: SessionRecoverySnapshot?) {
        self.snapshot = snapshot
    }

    func load() throws -> SessionRecoverySnapshot? {
        snapshot
    }

    func save(_ snapshot: SessionRecoverySnapshot) throws {
        self.snapshot = snapshot
    }

    func markInterrupted() throws {
        snapshot = nil
    }

    func clear() throws {
        snapshot = nil
    }
}

private enum BrowserTestError: Error, Equatable {
    case disconnected
}
