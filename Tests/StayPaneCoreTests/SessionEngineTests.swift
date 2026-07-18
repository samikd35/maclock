import Foundation
import Testing
@testable import StayPaneCore

@MainActor
@Test func sessionMovesThroughEveryTicketOneStateAndCompletesOnTime() throws {
    let clock = FakeClock(now: Date(timeIntervalSince1970: 1_000))
    let enforcement = FakeEnforcement()
    let engine = SessionEngine(clock: clock, enforcement: enforcement)
    let target = ApplicationTarget(
        displayName: "Writing App",
        bundleIdentifier: "com.example.writing",
        processIdentifier: 42
    )

    #expect(engine.state == .idle)

    engine.beginConfiguration()
    guard case let .configuring(draft) = engine.state else {
        Issue.record("Expected configuring")
        return
    }
    #expect(draft.duration == .default)
    #expect(draft.target == nil)

    engine.select(target: target)
    guard case let .ready(readyDraft) = engine.state else {
        Issue.record("Expected ready")
        return
    }
    #expect(readyDraft.target == target)

    try engine.beginStartCountdown()
    guard case let .starting(plan, startsAt) = engine.state else {
        Issue.record("Expected starting")
        return
    }
    #expect(plan.target == target)
    #expect(startsAt == clock.now.addingTimeInterval(3))

    clock.advance(by: 2)
    try engine.advance()
    guard case .starting = engine.state else {
        Issue.record("Expected countdown to remain active before its boundary")
        return
    }
    #expect(enforcement.startedTargets.isEmpty)

    clock.advance(by: 1)
    try engine.advance()
    guard case let .enforcing(activeSession) = engine.state else {
        Issue.record("Expected enforcing")
        return
    }
    #expect(enforcement.startedTargets == [target])
    #expect(activeSession.endsAt == clock.now.addingTimeInterval(30 * 60))

    clock.advance(by: 30 * 60 - 1)
    try engine.advance()
    guard case .enforcing = engine.state else {
        Issue.record("Expected enforcement before the completion boundary")
        return
    }
    #expect(enforcement.stopCount == 0)

    clock.advance(by: 1)
    try engine.advance()
    guard case let .completed(completedSession) = engine.state else {
        Issue.record("Expected completed")
        return
    }
    #expect(completedSession.plan == plan)
    #expect(enforcement.stopCount == 1)
}

@MainActor
@Test func activeSessionConfigurationIsImmutableUntilReset() throws {
    let clock = FakeClock(now: Date(timeIntervalSince1970: 2_000))
    let enforcement = FakeEnforcement()
    let engine = SessionEngine(clock: clock, enforcement: enforcement)
    let originalTarget = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor",
        processIdentifier: 7
    )
    let otherTarget = ApplicationTarget(
        displayName: "Browser",
        bundleIdentifier: "com.example.browser",
        processIdentifier: 8
    )

    engine.beginConfiguration()
    engine.select(target: originalTarget)
    try engine.beginStartCountdown(seconds: 0)
    try engine.advance()
    let activeState = engine.state

    engine.beginConfiguration(duration: SessionDuration(seconds: 60)!)
    engine.select(target: otherTarget)

    #expect(engine.state == activeState)
    #expect(throws: SessionEngineError.invalidTransition) {
        try engine.setDuration(SessionDuration(seconds: 120)!)
    }

    engine.reset()
    #expect(engine.state == .idle)
    #expect(enforcement.stopCount == 1)
}

@MainActor
@Test func canceledCountdownNeverStartsEnforcement() throws {
    let clock = FakeClock(now: Date(timeIntervalSince1970: 3_000))
    let enforcement = FakeEnforcement()
    let engine = SessionEngine(clock: clock, enforcement: enforcement)
    let target = ApplicationTarget(
        displayName: "Notes",
        bundleIdentifier: "com.example.notes",
        processIdentifier: 9
    )

    engine.beginConfiguration()
    engine.select(target: target)
    try engine.beginStartCountdown()
    try engine.cancelStartCountdown()
    clock.advance(by: 10)
    try engine.advance()

    guard case let .ready(draft) = engine.state else {
        Issue.record("Expected ready after cancellation")
        return
    }
    #expect(draft.target == target)
    #expect(enforcement.startedTargets.isEmpty)
}

@MainActor
@Test func enforcementFailureReturnsToReadyWithoutAnActiveSession() throws {
    let clock = FakeClock(now: Date(timeIntervalSince1970: 4_000))
    let enforcement = FakeEnforcement()
    enforcement.startError = FakeEnforcementError.permissionDenied
    let engine = SessionEngine(clock: clock, enforcement: enforcement)
    let target = ApplicationTarget(
        displayName: "Pages",
        bundleIdentifier: "com.example.pages",
        processIdentifier: 10
    )

    engine.beginConfiguration()
    engine.select(target: target)
    try engine.beginStartCountdown(seconds: 0)

    #expect(throws: FakeEnforcementError.permissionDenied) {
        try engine.advance()
    }
    guard case let .ready(draft) = engine.state else {
        Issue.record("Expected ready after enforcement failed")
        return
    }
    #expect(draft.target == target)
    #expect(enforcement.startedTargets.isEmpty)
    #expect(enforcement.stopCount == 0)
}

@MainActor
private final class FakeClock: SessionClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

@MainActor
private final class FakeEnforcement: SessionEnforcing {
    var startedTargets: [ApplicationTarget] = []
    var stopCount = 0
    var startError: FakeEnforcementError?

    func start(allowing target: ApplicationTarget) throws {
        if let startError {
            throw startError
        }
        startedTargets.append(target)
    }

    func stop() {
        stopCount += 1
    }
}

private enum FakeEnforcementError: Error {
    case permissionDenied
}
