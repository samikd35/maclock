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
    public let processIdentifier: Int32?
    public let applicationURL: URL?

    public init(
        displayName: String,
        bundleIdentifier: String,
        processIdentifier: Int32? = nil,
        applicationURL: URL? = nil
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.applicationURL = applicationURL
    }
}

public struct WindowIdentifier: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct WindowTarget: Equatable, Hashable, Identifiable, Sendable {
    public let id: WindowIdentifier
    public let title: String
    public let application: ApplicationTarget

    public init(
        id: WindowIdentifier,
        title: String,
        application: ApplicationTarget
    ) {
        self.id = id
        self.title = title
        self.application = application
    }
}

public enum TargetIdentifier: Equatable, Hashable, Sendable {
    case application(bundleIdentifier: String)
    case window(WindowIdentifier)
}

public enum SessionTarget: Equatable, Hashable, Sendable {
    case application(ApplicationTarget)
    case window(WindowTarget)

    public var id: TargetIdentifier {
        switch self {
        case let .application(application):
            .application(bundleIdentifier: application.bundleIdentifier)
        case let .window(window):
            .window(window.id)
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case let .application(application):
            application.bundleIdentifier
        case let .window(window):
            window.application.bundleIdentifier
        }
    }

}

public struct TargetSelectionPolicy: Equatable, Sendable {
    public private(set) var targets: [SessionTarget]

    public init(targets: [SessionTarget] = []) {
        self.targets = targets
    }

    @discardableResult
    public mutating func select(_ target: SessionTarget) -> Bool {
        switch target {
        case let .application(application):
            let insertionIndex = targets.firstIndex {
                $0.bundleIdentifier == application.bundleIdentifier
            }
            targets.removeAll {
                $0.bundleIdentifier == application.bundleIdentifier
            }
            targets.insert(
                target,
                at: min(insertionIndex ?? targets.endIndex, targets.endIndex)
            )
            return true

        case let .window(window):
            guard !targets.contains(where: {
                if case let .application(application) = $0 {
                    return application.bundleIdentifier
                        == window.application.bundleIdentifier
                }
                return false
            }) else {
                return false
            }

            if let index = targets.firstIndex(where: { $0.id == target.id }) {
                targets[index] = target
            } else {
                targets.append(target)
            }
            return true
        }
    }

    public mutating func deselect(_ identifier: TargetIdentifier) {
        targets.removeAll { $0.id == identifier }
    }
}

public enum WindowRelationship: Equatable, Hashable, Sendable {
    case independent
    case transient(ancestorWindowIdentifiers: [WindowIdentifier])
    case essentialSystemInterface
}

public struct ObservedWindow: Equatable, Hashable, Sendable {
    public let id: WindowIdentifier
    public let bundleIdentifier: String
    public let relationship: WindowRelationship

    public init(
        id: WindowIdentifier,
        bundleIdentifier: String,
        relationship: WindowRelationship
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.relationship = relationship
    }
}

public enum WindowActivationDecision: Equatable, Sendable {
    case allow
    case block(refocusTarget: TargetIdentifier?)
}

public struct WindowAllowlistPolicy: Equatable, Sendable {
    private let allowedApplicationBundleIdentifiers: Set<String>
    private let allowedWindowIdentifiers: Set<WindowIdentifier>
    private let fallbackTarget: TargetIdentifier?
    private var lastActivatedAllowedTarget: TargetIdentifier?

    public init(targets: [SessionTarget]) {
        allowedApplicationBundleIdentifiers = Set(targets.compactMap { target in
            guard case let .application(application) = target else {
                return nil
            }
            return application.bundleIdentifier
        })
        allowedWindowIdentifiers = Set(targets.compactMap { target in
            guard case let .window(window) = target else {
                return nil
            }
            return window.id
        })
        fallbackTarget = targets.first?.id
    }

    public func allows(_ window: ObservedWindow) -> Bool {
        if case .essentialSystemInterface = window.relationship {
            return true
        }
        return selectedTargetIdentifier(for: window) != nil
    }

    public mutating func handleActivation(
        _ window: ObservedWindow
    ) -> WindowActivationDecision {
        if case .essentialSystemInterface = window.relationship {
            return .allow
        }
        guard let selectedTarget = selectedTargetIdentifier(for: window) else {
            return .block(
                refocusTarget: lastActivatedAllowedTarget ?? fallbackTarget
            )
        }

        lastActivatedAllowedTarget = selectedTarget
        return .allow
    }

    private func selectedTargetIdentifier(
        for window: ObservedWindow
    ) -> TargetIdentifier? {
        if allowedApplicationBundleIdentifiers.contains(window.bundleIdentifier) {
            return .application(bundleIdentifier: window.bundleIdentifier)
        }
        if allowedWindowIdentifiers.contains(window.id) {
            return .window(window.id)
        }
        guard case let .transient(ancestorWindowIdentifiers) = window.relationship,
              let selectedAncestor = ancestorWindowIdentifiers.first(where: {
                  allowedWindowIdentifiers.contains($0)
              })
        else {
            return nil
        }
        return .window(selectedAncestor)
    }
}

public struct SessionDraft: Equatable, Sendable {
    public let duration: SessionDuration
    public let targets: [SessionTarget]

    public init(duration: SessionDuration, targets: [SessionTarget]) {
        self.duration = duration
        self.targets = targets
    }
}

public struct SessionPlan: Equatable, Sendable {
    public let id: UUID
    public let duration: SessionDuration
    public let targets: [SessionTarget]
    public let preparedAt: Date

    public init(
        id: UUID = UUID(),
        duration: SessionDuration,
        targets: [SessionTarget],
        preparedAt: Date
    ) {
        precondition(!targets.isEmpty, "A session plan requires at least one target")
        self.id = id
        self.duration = duration
        self.targets = targets
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
    func start(allowing targets: [SessionTarget]) throws
    func refresh() throws
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
            state = .configuring(SessionDraft(duration: duration, targets: []))
        default:
            break
        }
    }

    public func setDuration(_ duration: SessionDuration) throws {
        let draft = try editableDraft()
        let updatedDraft = SessionDraft(duration: duration, targets: draft.targets)
        state = updatedDraft.targets.isEmpty ? .configuring(updatedDraft) : .ready(updatedDraft)
    }

    public func select(target: ApplicationTarget) {
        select(target: .application(target))
    }

    public func select(target: SessionTarget) {
        guard case let .configuring(draft) = state else {
            if case let .ready(draft) = state {
                state = .ready(draft.selecting(target))
            }
            return
        }

        state = .ready(draft.selecting(target))
    }

    public func clearTargets() {
        guard case let .ready(draft) = state else {
            return
        }

        state = .configuring(SessionDraft(duration: draft.duration, targets: []))
    }

    public func deselectTarget(bundleIdentifier: String) {
        let draft: SessionDraft
        switch state {
        case let .configuring(currentDraft), let .ready(currentDraft):
            draft = currentDraft
        default:
            return
        }

        let updatedDraft = SessionDraft(
            duration: draft.duration,
            targets: draft.targets.filter {
                $0.bundleIdentifier != bundleIdentifier
            }
        )
        state = updatedDraft.targets.isEmpty
            ? .configuring(updatedDraft)
            : .ready(updatedDraft)
    }

    public func deselectTarget(_ identifier: TargetIdentifier) {
        let draft: SessionDraft
        switch state {
        case let .configuring(currentDraft), let .ready(currentDraft):
            draft = currentDraft
        default:
            return
        }

        var selectionPolicy = TargetSelectionPolicy(targets: draft.targets)
        selectionPolicy.deselect(identifier)
        let updatedDraft = SessionDraft(
            duration: draft.duration,
            targets: selectionPolicy.targets
        )
        state = updatedDraft.targets.isEmpty
            ? .configuring(updatedDraft)
            : .ready(updatedDraft)
    }

    public func beginStartCountdown(seconds: TimeInterval = 3) throws {
        guard case let .ready(draft) = state else {
            throw SessionEngineError.invalidTransition
        }
        guard !draft.targets.isEmpty else {
            throw SessionEngineError.targetRequired
        }

        let plan = SessionPlan(
            duration: draft.duration,
            targets: draft.targets,
            preparedAt: clock.now
        )
        state = .starting(plan: plan, startsAt: clock.now.addingTimeInterval(seconds))
    }

    public func cancelStartCountdown() throws {
        guard case let .starting(plan, _) = state else {
            throw SessionEngineError.invalidTransition
        }

        state = .ready(SessionDraft(duration: plan.duration, targets: plan.targets))
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
                try enforcement.start(allowing: plan.targets)
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
                state = .ready(SessionDraft(duration: plan.duration, targets: plan.targets))
                throw error
            }

        case let .enforcing(activeSession) where hasCompleted(activeSession):
            completeNormally(activeSession)

        case .enforcing:
            try enforcement.refresh()

        case let .resetPending(pendingReset)
            where hasCompleted(pendingReset.activeSession):
            completeNormally(pendingReset.activeSession)

        case .resetPending:
            try enforcement.refresh()

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

private extension SessionDraft {
    func selecting(_ target: SessionTarget) -> SessionDraft {
        var selectionPolicy = TargetSelectionPolicy(targets: targets)
        _ = selectionPolicy.select(target)
        return SessionDraft(duration: duration, targets: selectionPolicy.targets)
    }
}
