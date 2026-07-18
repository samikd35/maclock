import Foundation
import Testing
@testable import StayPaneCore

@MainActor
@Test func anActiveSessionResumesFromItsFixedEndTimeAfterRelaunch() throws {
    let store = InMemorySessionRecoveryStore()
    let originalClock = RecoveryTestClock(
        now: Date(timeIntervalSince1970: 1_000),
        continuousNow: 200
    )
    let originalEnforcement = RecoveryTestEnforcement()
    let originalEngine = SessionEngine(
        clock: originalClock,
        enforcement: originalEnforcement,
        recoveryStore: store
    )
    let target = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor"
    )

    originalEngine.beginConfiguration(duration: SessionDuration(seconds: 60)!)
    originalEngine.select(target: target)
    try originalEngine.beginStartCountdown(seconds: 0)
    try originalEngine.advance()

    let savedSnapshot = try store.load()
    let snapshot = try #require(savedSnapshot)
    #expect(snapshot.endsAt == Date(timeIntervalSince1970: 1_060))
    #expect(snapshot.plan.targets == [.application(target)])
    #expect(snapshot.phase == .enforcing)

    let relaunchedClock = RecoveryTestClock(
        now: Date(timeIntervalSince1970: 1_020),
        continuousNow: 5
    )
    let relaunchedEnforcement = RecoveryTestEnforcement()
    let relaunchedEngine = SessionEngine(
        clock: relaunchedClock,
        enforcement: relaunchedEnforcement,
        recoveryStore: store
    )

    let outcome = try relaunchedEngine.recover()

    #expect(outcome == .resumed)
    #expect(relaunchedEngine.remainingTime() == 40)
    #expect(relaunchedEnforcement.resumedAllowlists == [[.application(target)]])
    guard case let .enforcing(activeSession) = relaunchedEngine.state else {
        Issue.record("Expected recovered enforcement")
        return
    }
    #expect(activeSession.endsAt == Date(timeIntervalSince1970: 1_060))
    #expect(activeSession.plan.targets == [.application(target)])
}

@MainActor
@Test func aResetPendingSessionResumesBothFixedDeadlines() throws {
    let store = InMemorySessionRecoveryStore()
    let originalClock = RecoveryTestClock(
        now: Date(timeIntervalSince1970: 2_000),
        continuousNow: 50
    )
    let originalEngine = SessionEngine(
        clock: originalClock,
        enforcement: RecoveryTestEnforcement(),
        recoveryStore: store
    )
    let target = ApplicationTarget(
        displayName: "Research",
        bundleIdentifier: "com.example.research"
    )
    originalEngine.beginConfiguration(duration: SessionDuration(seconds: 120)!)
    originalEngine.select(target: target)
    try originalEngine.beginStartCountdown(seconds: 0)
    try originalEngine.advance()
    try originalEngine.requestEarlyReset(countdown: 30)

    let savedSnapshot = try store.load()
    let snapshot = try #require(savedSnapshot)
    #expect(
        snapshot.phase
            == .resetPending(
                requestedAt: Date(timeIntervalSince1970: 2_000),
                confirmationAvailableAt: Date(timeIntervalSince1970: 2_030)
            )
    )

    let relaunchedClock = RecoveryTestClock(
        now: Date(timeIntervalSince1970: 2_010),
        continuousNow: 3
    )
    let relaunchedEngine = SessionEngine(
        clock: relaunchedClock,
        enforcement: RecoveryTestEnforcement(),
        recoveryStore: store
    )

    #expect(try relaunchedEngine.recover() == .resumed)
    #expect(relaunchedEngine.remainingTime() == 110)
    #expect(relaunchedEngine.earlyResetRemainingTime() == 20)
    guard case let .resetPending(pendingReset) = relaunchedEngine.state else {
        Issue.record("Expected recovered reset-pending enforcement")
        return
    }
    #expect(
        pendingReset.confirmationAvailableAt
            == Date(timeIntervalSince1970: 2_030)
    )
}

@MainActor
@Test func anElapsedResetConfirmationIsImmediatelyAvailableAfterRecovery() throws {
    let store = InMemorySessionRecoveryStore()
    let target = ApplicationTarget(
        displayName: "Research",
        bundleIdentifier: "com.example.research"
    )
    let plan = SessionPlan(
        duration: SessionDuration(seconds: 120)!,
        targets: [.application(target)],
        preparedAt: Date(timeIntervalSince1970: 2_100)
    )
    try store.save(
        SessionRecoverySnapshot(
            plan: plan,
            startedAt: Date(timeIntervalSince1970: 2_100),
            endsAt: Date(timeIntervalSince1970: 2_220),
            phase: .resetPending(
                requestedAt: Date(timeIntervalSince1970: 2_105),
                confirmationAvailableAt: Date(timeIntervalSince1970: 2_135)
            )
        )
    )
    let engine = SessionEngine(
        clock: RecoveryTestClock(
            now: Date(timeIntervalSince1970: 2_140),
            continuousNow: 4
        ),
        enforcement: RecoveryTestEnforcement(),
        recoveryStore: store
    )

    #expect(try engine.recover() == .resumed)
    #expect(engine.earlyResetRemainingTime() == 0)
    #expect(engine.isEarlyResetConfirmationAvailable)
}

@MainActor
@Test func normalCompletionRemovesActiveRecoveryData() throws {
    let store = InMemorySessionRecoveryStore()
    let clock = RecoveryTestClock(
        now: Date(timeIntervalSince1970: 3_000),
        continuousNow: 10
    )
    let enforcement = RecoveryTestEnforcement()
    let engine = SessionEngine(
        clock: clock,
        enforcement: enforcement,
        recoveryStore: store
    )
    engine.beginConfiguration(duration: SessionDuration(seconds: 10)!)
    engine.select(
        target: ApplicationTarget(
            displayName: "Notes",
            bundleIdentifier: "com.example.notes"
        )
    )
    try engine.beginStartCountdown(seconds: 0)
    try engine.advance()
    #expect(try store.load() != nil)

    clock.advance(by: 10)
    try engine.advance()

    #expect(try store.load() == nil)
    #expect(enforcement.stopCount == 1)
    guard case .completed = engine.state else {
        Issue.record("Expected terminal completion")
        return
    }
}

@MainActor
@Test func permissionLossFailsOpenAsInterruptedAndCannotResume() throws {
    let store = InMemorySessionRecoveryStore()
    let clock = RecoveryTestClock(
        now: Date(timeIntervalSince1970: 4_000),
        continuousNow: 25
    )
    let enforcement = RecoveryTestEnforcement()
    let engine = SessionEngine(
        clock: clock,
        enforcement: enforcement,
        recoveryStore: store
    )
    let target = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor"
    )
    engine.beginConfiguration(duration: SessionDuration(seconds: 60)!)
    engine.select(target: target)
    try engine.beginStartCountdown(seconds: 0)
    try engine.advance()
    clock.advance(by: 12)

    try engine.interrupt(reason: .enforcementUnavailable)

    #expect(try store.load() == nil)
    #expect(enforcement.stopCount == 1)
    guard case let .interrupted(interruptedSession) = engine.state else {
        Issue.record("Expected Interrupted")
        return
    }
    #expect(interruptedSession.plan.targets == [.application(target)])
    #expect(interruptedSession.reason == .enforcementUnavailable)
    #expect(interruptedSession.actualFocusDuration == 12)

    let nextEngine = SessionEngine(
        clock: clock,
        enforcement: RecoveryTestEnforcement(),
        recoveryStore: store
    )
    #expect(try nextEngine.recover() == .none)
}

@MainActor
@Test func interruptionCannotResumeWhenActiveSnapshotDeletionFails() throws {
    let store = InMemorySessionRecoveryStore()
    let clock = RecoveryTestClock(
        now: Date(timeIntervalSince1970: 4_100),
        continuousNow: 10
    )
    let enforcement = RecoveryTestEnforcement()
    let engine = SessionEngine(
        clock: clock,
        enforcement: enforcement,
        recoveryStore: store
    )
    engine.beginConfiguration(duration: SessionDuration(seconds: 60)!)
    engine.select(
        target: ApplicationTarget(
            displayName: "Editor",
            bundleIdentifier: "com.example.editor"
        )
    )
    try engine.beginStartCountdown(seconds: 0)
    try engine.advance()
    store.clearError = .unavailable

    try engine.interrupt(reason: .enforcementUnavailable)

    #expect(store.hasInterruptionMarker)
    #expect(enforcement.stopCount == 1)
    let nextEngine = SessionEngine(
        clock: clock,
        enforcement: RecoveryTestEnforcement(),
        recoveryStore: store
    )
    #expect(try nextEngine.recover() == .none)
}

@MainActor
@Test func failedRelaunchRecoveryFailsOpenAsInterrupted() throws {
    let store = InMemorySessionRecoveryStore()
    let target = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor"
    )
    let plan = SessionPlan(
        duration: SessionDuration(seconds: 60)!,
        targets: [.application(target)],
        preparedAt: Date(timeIntervalSince1970: 5_000)
    )
    try store.save(
        SessionRecoverySnapshot(
            plan: plan,
            startedAt: Date(timeIntervalSince1970: 5_000),
            endsAt: Date(timeIntervalSince1970: 5_060),
            phase: .enforcing
        )
    )
    let enforcement = RecoveryTestEnforcement()
    enforcement.resumeError = .unavailable
    let engine = SessionEngine(
        clock: RecoveryTestClock(
            now: Date(timeIntervalSince1970: 5_010),
            continuousNow: 2
        ),
        enforcement: enforcement,
        recoveryStore: store
    )

    #expect(throws: RecoveryTestError.unavailable) {
        try engine.recover()
    }

    #expect(try store.load() == nil)
    #expect(enforcement.stopCount == 1)
    guard case let .interrupted(interruptedSession) = engine.state else {
        Issue.record("Expected failed recovery to produce Interrupted")
        return
    }
    #expect(interruptedSession.reason == .recoveryUnavailable)
    #expect(interruptedSession.plan == plan)
}

@MainActor
@Test func confirmedEarlyResetRemovesActiveRecoveryData() throws {
    let store = InMemorySessionRecoveryStore()
    let clock = RecoveryTestClock(
        now: Date(timeIntervalSince1970: 6_000),
        continuousNow: 10
    )
    let enforcement = RecoveryTestEnforcement()
    let engine = SessionEngine(
        clock: clock,
        enforcement: enforcement,
        recoveryStore: store
    )
    engine.beginConfiguration(duration: SessionDuration(seconds: 60)!)
    engine.select(
        target: ApplicationTarget(
            displayName: "Editor",
            bundleIdentifier: "com.example.editor"
        )
    )
    try engine.beginStartCountdown(seconds: 0)
    try engine.advance()
    try engine.requestEarlyReset(countdown: 0)

    try engine.confirmEarlyReset()

    #expect(try store.load() == nil)
    #expect(enforcement.stopCount == 1)
    guard case .endedEarly = engine.state else {
        Issue.record("Expected Ended Early")
        return
    }
}

@MainActor
@Test func cancelingEarlyResetPersistsTheUnchangedActiveSession() throws {
    let store = InMemorySessionRecoveryStore()
    let clock = RecoveryTestClock(
        now: Date(timeIntervalSince1970: 7_000),
        continuousNow: 10
    )
    let engine = SessionEngine(
        clock: clock,
        enforcement: RecoveryTestEnforcement(),
        recoveryStore: store
    )
    engine.beginConfiguration(duration: SessionDuration(seconds: 60)!)
    engine.select(
        target: ApplicationTarget(
            displayName: "Editor",
            bundleIdentifier: "com.example.editor"
        )
    )
    try engine.beginStartCountdown(seconds: 0)
    try engine.advance()
    try engine.requestEarlyReset()

    try engine.cancelEarlyReset()

    let savedSnapshot = try store.load()
    #expect(try #require(savedSnapshot).phase == .enforcing)
    guard case .enforcing = engine.state else {
        Issue.record("Expected unchanged active enforcement")
        return
    }
}

@MainActor
@Test func decliningFinalResetConfirmationPersistsActiveEnforcement() throws {
    let store = InMemorySessionRecoveryStore()
    let clock = RecoveryTestClock(
        now: Date(timeIntervalSince1970: 8_000),
        continuousNow: 10
    )
    let engine = SessionEngine(
        clock: clock,
        enforcement: RecoveryTestEnforcement(),
        recoveryStore: store
    )
    engine.beginConfiguration(duration: SessionDuration(seconds: 60)!)
    engine.select(
        target: ApplicationTarget(
            displayName: "Editor",
            bundleIdentifier: "com.example.editor"
        )
    )
    try engine.beginStartCountdown(seconds: 0)
    try engine.advance()
    try engine.requestEarlyReset(countdown: 30)
    clock.advance(by: 30)

    try engine.declineEarlyResetConfirmation()

    let savedSnapshot = try store.load()
    #expect(try #require(savedSnapshot).phase == .enforcing)
    guard case .enforcing = engine.state else {
        Issue.record("Expected active enforcement after declining reset")
        return
    }
}

@MainActor
@Test func anExpiredOfflineSessionRestoresAndCompletesInsteadOfResuming() throws {
    let store = InMemorySessionRecoveryStore()
    let target = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor"
    )
    let plan = SessionPlan(
        duration: SessionDuration(seconds: 60)!,
        targets: [.application(target)],
        preparedAt: Date(timeIntervalSince1970: 9_000)
    )
    try store.save(
        SessionRecoverySnapshot(
            plan: plan,
            startedAt: Date(timeIntervalSince1970: 9_000),
            endsAt: Date(timeIntervalSince1970: 9_060),
            phase: .enforcing
        )
    )
    let enforcement = RecoveryTestEnforcement()
    let engine = SessionEngine(
        clock: RecoveryTestClock(
            now: Date(timeIntervalSince1970: 9_120),
            continuousNow: 1
        ),
        enforcement: enforcement,
        recoveryStore: store
    )

    #expect(try engine.recover() == .completedWhileUnavailable)

    #expect(enforcement.resumedAllowlists.isEmpty)
    #expect(enforcement.stopCount == 1)
    #expect(try store.load() == nil)
    guard case let .completed(completedSession) = engine.state else {
        Issue.record("Expected Completed cleanup")
        return
    }
    #expect(completedSession.completedAt == Date(timeIntervalSince1970: 9_060))
}

@MainActor
private final class InMemorySessionRecoveryStore: SessionRecoveryPersisting {
    private var snapshot: SessionRecoverySnapshot?
    var clearError: RecoveryTestError?
    private(set) var hasInterruptionMarker = false

    func load() throws -> SessionRecoverySnapshot? {
        snapshot
    }

    func save(_ snapshot: SessionRecoverySnapshot) throws {
        self.snapshot = snapshot
        hasInterruptionMarker = false
    }

    func markInterrupted(
        at interruptedAt: Date,
        reason: SessionInterruptionReason
    ) throws {
        snapshot = nil
        hasInterruptionMarker = true
    }

    func clear() throws {
        if let clearError {
            throw clearError
        }
        snapshot = nil
        hasInterruptionMarker = false
    }
}

@MainActor
private final class RecoveryTestClock: SessionClock {
    var now: Date
    var continuousNow: TimeInterval

    init(now: Date, continuousNow: TimeInterval) {
        self.now = now
        self.continuousNow = continuousNow
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        continuousNow += seconds
    }
}

@MainActor
private final class RecoveryTestEnforcement: SessionEnforcing {
    var resumedAllowlists: [[SessionTarget]] = []
    var stopCount = 0
    var resumeError: RecoveryTestError?

    func start(allowing targets: [SessionTarget]) throws {}

    func resume(allowing targets: [SessionTarget]) throws {
        if let resumeError {
            throw resumeError
        }
        resumedAllowlists.append(targets)
    }

    func refresh() throws {}

    func stop() {
        stopCount += 1
    }
}

private enum RecoveryTestError: Error, Equatable {
    case unavailable
}
