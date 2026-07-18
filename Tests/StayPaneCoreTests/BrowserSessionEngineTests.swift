import Foundation
import Testing
@testable import StayPaneCore

@MainActor
@Test func disconnectedBrowserPreflightRefusesToStartATabSession() throws {
    let browser = BrowserTestEnforcement(preflightError: .disconnected)
    let engine = SessionEngine(
        clock: BrowserTestClock(),
        enforcement: BrowserTestNativeEnforcement(),
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
    #expect(browser.preflightTargets == [tab])
}

@MainActor
@Test func tabSessionCoordinatesNativeAndBrowserEnforcementUntilCompletion() throws {
    let clock = BrowserTestClock()
    let native = BrowserTestNativeEnforcement()
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
    #expect(browser.startedTargets == [tab])
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
@Test func lostBrowserConnectionCanFailOpenAnActiveTabSession() throws {
    let clock = BrowserTestClock()
    let native = BrowserTestNativeEnforcement()
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
    let clock = BrowserTestClock()
    let tab = makeBrowserTabTarget()
    let recovery = BrowserTestRecoveryStore(
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
    let native = BrowserTestNativeEnforcement()
    let browser = BrowserTestEnforcement()
    let engine = SessionEngine(
        clock: clock,
        enforcement: native,
        browserEnforcement: browser,
        recoveryStore: recovery
    )

    #expect(try engine.recover() == .resumed)

    #expect(native.startedTargets == [.application(tab.application)])
    #expect(browser.startedTargets == [tab])
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
private final class BrowserTestClock: SessionClock {
    var now = Date(timeIntervalSince1970: 80_000)
    var continuousNow: TimeInterval = 200

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        continuousNow += seconds
    }
}

@MainActor
private final class BrowserTestNativeEnforcement: SessionEnforcing {
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
private final class BrowserTestEnforcement: BrowserSessionEnforcing {
    private let preflightError: BrowserTestError?
    private(set) var preflightTargets: [BrowserTabTarget] = []
    private(set) var startedTargets: [BrowserTabTarget] = []
    private(set) var stopCount = 0
    var refreshError: BrowserTestError?

    init(preflightError: BrowserTestError? = nil) {
        self.preflightError = preflightError
    }

    func preflight(targets: [BrowserTabTarget]) throws {
        preflightTargets = targets
        if let preflightError {
            throw preflightError
        }
    }

    func start(allowing targets: [BrowserTabTarget]) throws {
        startedTargets = targets
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
private final class BrowserTestRecoveryStore: SessionRecoveryPersisting {
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
