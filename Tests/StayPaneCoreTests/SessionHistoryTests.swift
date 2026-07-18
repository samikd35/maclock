import Foundation
import Testing
@testable import StayPaneCore

@MainActor
@Test func normalCompletionRecordsOnlyTheMinimalCompletedHistory() throws {
    let clock = HistoryTestClock(
        now: Date(timeIntervalSince1970: 30_000),
        continuousNow: 50
    )
    let history = InMemorySessionHistoryStore()
    let engine = SessionEngine(
        clock: clock,
        enforcement: HistoryTestEnforcement(),
        historyStore: history
    )
    engine.beginConfiguration(duration: SessionDuration(seconds: 10)!)
    engine.select(
        target: .application(
            ApplicationTarget(
                displayName: "Private Editor",
                bundleIdentifier: "com.example.private-editor"
            )
        )
    )
    try engine.beginStartCountdown(seconds: 0)
    try engine.advance()
    clock.advance(by: 10)

    try engine.advance()

    #expect(
        try history.load() == [
            SessionHistoryRecord(
                startedAt: Date(timeIntervalSince1970: 30_000),
                plannedDuration: SessionDuration(seconds: 10)!,
                actualFocusTime: 10,
                result: .completed
            )
        ]
    )
}

@MainActor
@Test func confirmedEarlyResetRecordsEndedEarlyHistory() throws {
    let clock = HistoryTestClock(
        now: Date(timeIntervalSince1970: 31_000),
        continuousNow: 80
    )
    let history = InMemorySessionHistoryStore()
    let engine = SessionEngine(
        clock: clock,
        enforcement: HistoryTestEnforcement(),
        historyStore: history
    )
    engine.beginConfiguration(duration: SessionDuration(seconds: 60)!)
    engine.select(
        target: ApplicationTarget(
            displayName: "Private Notes",
            bundleIdentifier: "com.example.private-notes"
        )
    )
    try engine.beginStartCountdown(seconds: 0)
    try engine.advance()
    clock.advance(by: 12)
    try engine.requestEarlyReset(countdown: 0)

    try engine.confirmEarlyReset()

    #expect(
        try history.load() == [
            SessionHistoryRecord(
                startedAt: Date(timeIntervalSince1970: 31_000),
                plannedDuration: SessionDuration(seconds: 60)!,
                actualFocusTime: 12,
                result: .endedEarly
            )
        ]
    )
}

@MainActor
@Test func failOpenRecordsInterruptedHistory() throws {
    let clock = HistoryTestClock(
        now: Date(timeIntervalSince1970: 32_000),
        continuousNow: 100
    )
    let history = InMemorySessionHistoryStore()
    let engine = SessionEngine(
        clock: clock,
        enforcement: HistoryTestEnforcement(),
        historyStore: history
    )
    engine.beginConfiguration(duration: SessionDuration(seconds: 60)!)
    engine.select(
        target: ApplicationTarget(
            displayName: "Confidential Browser",
            bundleIdentifier: "com.example.confidential-browser"
        )
    )
    try engine.beginStartCountdown(seconds: 0)
    try engine.advance()
    clock.advance(by: 9)

    try engine.interrupt(reason: .enforcementUnavailable)

    #expect(
        try history.load() == [
            SessionHistoryRecord(
                startedAt: Date(timeIntervalSince1970: 32_000),
                plannedDuration: SessionDuration(seconds: 60)!,
                actualFocusTime: 9,
                result: .interrupted
            )
        ]
    )
}

@MainActor
@Test func expiredOfflineRecoveryRecordsCompletedHistory() throws {
    let recovery = HistoryTestRecoveryStore()
    let history = InMemorySessionHistoryStore()
    let plan = SessionPlan(
        duration: SessionDuration(seconds: 60)!,
        targets: [
            .application(
                ApplicationTarget(
                    displayName: "Private Editor",
                    bundleIdentifier: "com.example.private-editor"
                )
            )
        ],
        preparedAt: Date(timeIntervalSince1970: 33_000)
    )
    try recovery.save(
        SessionRecoverySnapshot(
            plan: plan,
            startedAt: Date(timeIntervalSince1970: 33_000),
            endsAt: Date(timeIntervalSince1970: 33_060),
            phase: .enforcing
        )
    )
    let engine = SessionEngine(
        clock: HistoryTestClock(
            now: Date(timeIntervalSince1970: 33_120),
            continuousNow: 2
        ),
        enforcement: HistoryTestEnforcement(),
        recoveryStore: recovery,
        historyStore: history
    )

    #expect(try engine.recover() == .completedWhileUnavailable)

    #expect(
        try history.load() == [
            SessionHistoryRecord(
                startedAt: Date(timeIntervalSince1970: 33_000),
                plannedDuration: SessionDuration(seconds: 60)!,
                actualFocusTime: 60,
                result: .completed
            )
        ]
    )
}

@MainActor
@Test func failedRecoveryRecordsInterruptedHistory() throws {
    let recovery = HistoryTestRecoveryStore()
    let history = InMemorySessionHistoryStore()
    let plan = SessionPlan(
        duration: SessionDuration(seconds: 60)!,
        targets: [
            .application(
                ApplicationTarget(
                    displayName: "Private Editor",
                    bundleIdentifier: "com.example.private-editor"
                )
            )
        ],
        preparedAt: Date(timeIntervalSince1970: 34_000)
    )
    try recovery.save(
        SessionRecoverySnapshot(
            plan: plan,
            startedAt: Date(timeIntervalSince1970: 34_000),
            endsAt: Date(timeIntervalSince1970: 34_060),
            phase: .enforcing
        )
    )
    let engine = SessionEngine(
        clock: HistoryTestClock(
            now: Date(timeIntervalSince1970: 34_010),
            continuousNow: 2
        ),
        enforcement: FailingHistoryRecoveryEnforcement(),
        recoveryStore: recovery,
        historyStore: history
    )

    #expect(throws: HistoryTestError.unavailable) {
        try engine.recover()
    }

    #expect(
        try history.load() == [
            SessionHistoryRecord(
                startedAt: Date(timeIntervalSince1970: 34_000),
                plannedDuration: SessionDuration(seconds: 60)!,
                actualFocusTime: 10,
                result: .interrupted
            )
        ]
    )
}

@MainActor
private final class InMemorySessionHistoryStore: SessionHistoryStoring {
    private var records: [SessionHistoryRecord] = []

    func load() throws -> [SessionHistoryRecord] {
        records
    }

    func record(_ record: SessionHistoryRecord) throws {
        records.append(record)
    }

    func clear() throws {
        records.removeAll()
    }
}

@MainActor
private final class HistoryTestClock: SessionClock {
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
private final class HistoryTestEnforcement: SessionEnforcing {
    func start(allowing targets: [SessionTarget]) throws {}
    func refresh() throws {}
    func stop() {}
}

@MainActor
private final class HistoryTestRecoveryStore: SessionRecoveryPersisting {
    private var snapshot: SessionRecoverySnapshot?

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

@MainActor
private final class FailingHistoryRecoveryEnforcement: SessionEnforcing {
    func start(allowing targets: [SessionTarget]) throws {}

    func resume(allowing targets: [SessionTarget]) throws {
        throw HistoryTestError.unavailable
    }

    func refresh() throws {}
    func stop() {}
}

private enum HistoryTestError: Error, Equatable {
    case unavailable
}
