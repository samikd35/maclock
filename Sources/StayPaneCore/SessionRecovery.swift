import Foundation

public enum SessionRecoveryPhase: Codable, Equatable, Sendable {
    case enforcing
    case resetPending(
        requestedAt: Date,
        confirmationAvailableAt: Date
    )
}

public struct SessionRecoverySnapshot: Codable, Equatable, Sendable {
    public let plan: SessionPlan
    public let startedAt: Date
    public let endsAt: Date
    public let phase: SessionRecoveryPhase

    public init(
        plan: SessionPlan,
        startedAt: Date,
        endsAt: Date,
        phase: SessionRecoveryPhase
    ) {
        self.plan = plan
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.phase = phase
    }

    public init(activeSession: ActiveSession) {
        self.init(
            plan: activeSession.plan,
            startedAt: activeSession.startedAt,
            endsAt: activeSession.endsAt,
            phase: .enforcing
        )
    }

    public init(pendingReset: ResetPendingSession) {
        self.init(
            plan: pendingReset.activeSession.plan,
            startedAt: pendingReset.activeSession.startedAt,
            endsAt: pendingReset.activeSession.endsAt,
            phase: .resetPending(
                requestedAt: pendingReset.requestedAt,
                confirmationAvailableAt: pendingReset.confirmationAvailableAt
            )
        )
    }
}

public enum SessionRecoveryOutcome: Equatable, Sendable {
    case none
    case resumed
    case completedWhileUnavailable
}

@MainActor
public protocol SessionRecoveryPersisting: AnyObject {
    func load() throws -> SessionRecoverySnapshot?
    func save(_ snapshot: SessionRecoverySnapshot) throws
    func markInterrupted() throws
    func clear() throws
}

@MainActor
public final class NoSessionRecoveryStore: SessionRecoveryPersisting {
    public init() {}

    public func load() throws -> SessionRecoverySnapshot? {
        nil
    }

    public func save(_ snapshot: SessionRecoverySnapshot) throws {}

    public func markInterrupted() throws {}

    public func clear() throws {}
}
