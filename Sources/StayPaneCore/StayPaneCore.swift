import Foundation

public struct SessionDuration: Equatable, Hashable, Codable, Sendable {
    public static let minimumSeconds = 10
    public static let maximumSeconds = 24 * 60 * 60
    public static let `default` = SessionDuration(uncheckedSeconds: 30 * 60)

    public let seconds: Int

    public init?(seconds: Int) {
        guard Self.minimumSeconds...Self.maximumSeconds ~= seconds else {
            return nil
        }

        self.seconds = seconds
    }

    public var timeInterval: TimeInterval {
        TimeInterval(seconds)
    }

    private init(uncheckedSeconds: Int) {
        seconds = uncheckedSeconds
    }
}

public struct ApplicationTarget: Equatable, Hashable, Sendable {
    public let displayName: String
    public let bundleIdentifier: String
    public let processIdentifier: Int32

    public init(displayName: String, bundleIdentifier: String, processIdentifier: Int32) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }
}

public struct SessionDraft: Equatable, Sendable {
    public let duration: SessionDuration
    public let target: ApplicationTarget?

    public init(duration: SessionDuration, target: ApplicationTarget?) {
        self.duration = duration
        self.target = target
    }
}

public struct SessionPlan: Equatable, Sendable {
    public let id: UUID
    public let duration: SessionDuration
    public let target: ApplicationTarget
    public let preparedAt: Date

    public init(
        id: UUID = UUID(),
        duration: SessionDuration,
        target: ApplicationTarget,
        preparedAt: Date
    ) {
        self.id = id
        self.duration = duration
        self.target = target
        self.preparedAt = preparedAt
    }
}

public struct ActiveSession: Equatable, Sendable {
    public let plan: SessionPlan
    public let startedAt: Date
    public let endsAt: Date
    public let continuousStartedAt: TimeInterval
    public let continuousEndsAt: TimeInterval

    public init(
        plan: SessionPlan,
        startedAt: Date,
        endsAt: Date,
        continuousStartedAt: TimeInterval,
        continuousEndsAt: TimeInterval
    ) {
        self.plan = plan
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.continuousStartedAt = continuousStartedAt
        self.continuousEndsAt = continuousEndsAt
    }
}

public struct CompletedSession: Equatable, Sendable {
    public let plan: SessionPlan
    public let completedAt: Date

    public init(plan: SessionPlan, completedAt: Date) {
        self.plan = plan
        self.completedAt = completedAt
    }
}

public struct ResetPendingSession: Equatable, Sendable {
    public let activeSession: ActiveSession
    public let requestedAt: Date
    public let confirmationAvailableAt: Date
    public let continuousConfirmationAvailableAt: TimeInterval

    public init(
        activeSession: ActiveSession,
        requestedAt: Date,
        confirmationAvailableAt: Date,
        continuousConfirmationAvailableAt: TimeInterval
    ) {
        self.activeSession = activeSession
        self.requestedAt = requestedAt
        self.confirmationAvailableAt = confirmationAvailableAt
        self.continuousConfirmationAvailableAt = continuousConfirmationAvailableAt
    }
}

public struct EndedEarlySession: Equatable, Sendable {
    public let plan: SessionPlan
    public let startedAt: Date
    public let endedAt: Date
    public let actualFocusDuration: TimeInterval

    public init(
        plan: SessionPlan,
        startedAt: Date,
        endedAt: Date,
        actualFocusDuration: TimeInterval
    ) {
        self.plan = plan
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.actualFocusDuration = actualFocusDuration
    }
}

public enum SessionState: Equatable, Sendable {
    case idle
    case configuring(SessionDraft)
    case ready(SessionDraft)
    case starting(plan: SessionPlan, startsAt: Date)
    case enforcing(ActiveSession)
    case resetPending(ResetPendingSession)
    case completed(CompletedSession)
    case endedEarly(EndedEarlySession)
}

public enum SessionEngineError: Error, Equatable {
    case invalidTransition
    case targetRequired
    case earlyResetConfirmationNotReady
}

public enum QuitDecision: Equatable, Sendable {
    case terminateNow
    case beginEarlyReset
    case waitForRestoration
}

public struct QuitCoordinator: Equatable, Sendable {
    private var isQuitPending = false

    public init() {}

    public mutating func requestQuit(
        isSessionActive: Bool,
        pendingRestorationCount: Int
    ) -> QuitDecision {
        if isSessionActive {
            isQuitPending = true
            return .beginEarlyReset
        }
        if pendingRestorationCount > 0 {
            isQuitPending = true
            return .waitForRestoration
        }

        isQuitPending = false
        return .terminateNow
    }

    public mutating func consumeQuitWhenSafe(
        isSessionActive: Bool,
        pendingRestorationCount: Int
    ) -> Bool {
        guard isQuitPending, !isSessionActive, pendingRestorationCount == 0 else {
            return false
        }

        isQuitPending = false
        return true
    }

    public mutating func cancelDeferredQuit() {
        isQuitPending = false
    }
}

@MainActor
public protocol SessionClock: AnyObject {
    var now: Date { get }
    var continuousNow: TimeInterval { get }
}

@MainActor
public protocol SessionEnforcing: AnyObject {
    func start(allowing target: ApplicationTarget) throws
    func stop()
}

@MainActor
public final class SessionEngine {
    public private(set) var state: SessionState = .idle

    private let clock: any SessionClock
    private let enforcement: any SessionEnforcing

    public init(clock: any SessionClock, enforcement: any SessionEnforcing) {
        self.clock = clock
        self.enforcement = enforcement
    }

    public func beginConfiguration(duration: SessionDuration = .default) {
        switch state {
        case .idle, .completed, .endedEarly:
            state = .configuring(SessionDraft(duration: duration, target: nil))
        default:
            break
        }
    }

    public func setDuration(_ duration: SessionDuration) throws {
        let draft = try editableDraft()
        let updatedDraft = SessionDraft(duration: duration, target: draft.target)
        state = updatedDraft.target == nil ? .configuring(updatedDraft) : .ready(updatedDraft)
    }

    public func select(target: ApplicationTarget) {
        guard case let .configuring(draft) = state else {
            if case let .ready(draft) = state {
                state = .ready(SessionDraft(duration: draft.duration, target: target))
            }
            return
        }

        state = .ready(SessionDraft(duration: draft.duration, target: target))
    }

    public func clearTarget() {
        guard case let .ready(draft) = state else {
            return
        }

        state = .configuring(SessionDraft(duration: draft.duration, target: nil))
    }

    public func beginStartCountdown(seconds: TimeInterval = 3) throws {
        guard case let .ready(draft) = state else {
            throw SessionEngineError.invalidTransition
        }
        guard let target = draft.target else {
            throw SessionEngineError.targetRequired
        }

        let plan = SessionPlan(duration: draft.duration, target: target, preparedAt: clock.now)
        state = .starting(plan: plan, startsAt: clock.now.addingTimeInterval(seconds))
    }

    public func cancelStartCountdown() throws {
        guard case let .starting(plan, _) = state else {
            throw SessionEngineError.invalidTransition
        }

        state = .ready(SessionDraft(duration: plan.duration, target: plan.target))
    }

    public func requestEarlyReset(countdown: TimeInterval = 30) throws {
        guard case let .enforcing(activeSession) = state else {
            throw SessionEngineError.invalidTransition
        }
        if hasCompleted(activeSession) {
            completeNormally(activeSession)
            return
        }

        state = .resetPending(
            ResetPendingSession(
                activeSession: activeSession,
                requestedAt: clock.now,
                confirmationAvailableAt: clock.now.addingTimeInterval(countdown),
                continuousConfirmationAvailableAt: clock.continuousNow + countdown
            )
        )
    }

    public func cancelEarlyReset() throws {
        guard case let .resetPending(pendingReset) = state else {
            throw SessionEngineError.invalidTransition
        }
        if hasCompleted(pendingReset.activeSession) {
            completeNormally(pendingReset.activeSession)
            return
        }

        state = .enforcing(pendingReset.activeSession)
    }

    public func confirmEarlyReset() throws {
        guard case let .resetPending(pendingReset) = state else {
            throw SessionEngineError.invalidTransition
        }
        if hasCompleted(pendingReset.activeSession) {
            completeNormally(pendingReset.activeSession)
            return
        }
        guard clock.continuousNow >= pendingReset.continuousConfirmationAvailableAt else {
            throw SessionEngineError.earlyResetConfirmationNotReady
        }

        enforcement.stop()
        let activeSession = pendingReset.activeSession
        state = .endedEarly(
            EndedEarlySession(
                plan: activeSession.plan,
                startedAt: activeSession.startedAt,
                endedAt: clock.now,
                actualFocusDuration: max(
                    0,
                    clock.continuousNow - activeSession.continuousStartedAt
                )
            )
        )
    }

    public func declineEarlyResetConfirmation() throws {
        guard case let .resetPending(pendingReset) = state else {
            throw SessionEngineError.invalidTransition
        }
        if hasCompleted(pendingReset.activeSession) {
            completeNormally(pendingReset.activeSession)
            return
        }
        guard clock.continuousNow >= pendingReset.continuousConfirmationAvailableAt else {
            throw SessionEngineError.earlyResetConfirmationNotReady
        }

        state = .enforcing(pendingReset.activeSession)
    }

    public func advance() throws {
        switch state {
        case let .starting(plan, startsAt) where clock.now >= startsAt:
            do {
                try enforcement.start(allowing: plan.target)
                state = .enforcing(
                    ActiveSession(
                        plan: plan,
                        startedAt: clock.now,
                        endsAt: clock.now.addingTimeInterval(plan.duration.timeInterval),
                        continuousStartedAt: clock.continuousNow,
                        continuousEndsAt: clock.continuousNow + plan.duration.timeInterval
                    )
                )
            } catch {
                state = .ready(SessionDraft(duration: plan.duration, target: plan.target))
                throw error
            }

        case let .enforcing(activeSession) where hasCompleted(activeSession):
            completeNormally(activeSession)

        case let .resetPending(pendingReset)
            where hasCompleted(pendingReset.activeSession):
            completeNormally(pendingReset.activeSession)

        default:
            break
        }
    }

    public func reset() {
        if case .enforcing = state {
            enforcement.stop()
        } else if case .resetPending = state {
            enforcement.stop()
        }
        state = .idle
    }

    public func remainingTime() -> TimeInterval? {
        switch state {
        case let .starting(_, startsAt):
            max(0, startsAt.timeIntervalSince(clock.now))
        case let .enforcing(activeSession):
            max(0, activeSession.continuousEndsAt - clock.continuousNow)
        case let .resetPending(pendingReset):
            max(
                0,
                pendingReset.activeSession.continuousEndsAt - clock.continuousNow
            )
        default:
            nil
        }
    }

    public func earlyResetRemainingTime() -> TimeInterval? {
        guard case let .resetPending(pendingReset) = state else {
            return nil
        }
        return max(
            0,
            pendingReset.continuousConfirmationAvailableAt - clock.continuousNow
        )
    }

    public var isEarlyResetConfirmationAvailable: Bool {
        guard case let .resetPending(pendingReset) = state else {
            return false
        }
        return clock.continuousNow >= pendingReset.continuousConfirmationAvailableAt
    }

    private func hasCompleted(_ activeSession: ActiveSession) -> Bool {
        clock.continuousNow >= activeSession.continuousEndsAt
    }

    private func completeNormally(_ activeSession: ActiveSession) {
        enforcement.stop()
        state = .completed(
            CompletedSession(plan: activeSession.plan, completedAt: clock.now)
        )
    }

    private func editableDraft() throws -> SessionDraft {
        switch state {
        case let .configuring(draft), let .ready(draft):
            draft
        default:
            throw SessionEngineError.invalidTransition
        }
    }
}
