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

public struct ApplicationTarget: Codable, Equatable, Hashable, Sendable {
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

public struct WindowIdentifier: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct WindowTarget: Codable, Equatable, Hashable, Identifiable, Sendable {
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

public enum TargetIdentifier: Codable, Equatable, Hashable, Sendable {
    case application(bundleIdentifier: String)
    case window(WindowIdentifier)
    case browserTab(
        profileIdentifier: BrowserProfileIdentifier,
        tabIdentifier: BrowserTabIdentifier
    )
}

public enum SessionTarget: Codable, Equatable, Hashable, Sendable {
    case application(ApplicationTarget)
    case window(WindowTarget)
    case browserTab(BrowserTabTarget)

    public var id: TargetIdentifier {
        switch self {
        case let .application(application):
            .application(bundleIdentifier: application.bundleIdentifier)
        case let .window(window):
            .window(window.id)
        case let .browserTab(tab):
            .browserTab(
                profileIdentifier: tab.profileIdentifier,
                tabIdentifier: tab.tabIdentifier
            )
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case let .application(application):
            application.bundleIdentifier
        case let .window(window):
            window.application.bundleIdentifier
        case let .browserTab(tab):
            tab.application.bundleIdentifier
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
                switch $0 {
                case let .application(application):
                    application.bundleIdentifier == window.application.bundleIdentifier
                case let .browserTab(tab):
                    tab.application.bundleIdentifier == window.application.bundleIdentifier
                case .window:
                    false
                }
            }) else {
                return false
            }

            if let index = targets.firstIndex(where: { $0.id == target.id }) {
                targets[index] = target
            } else {
                targets.append(target)
            }
            return true

        case let .browserTab(tab):
            let insertionIndex = targets.firstIndex {
                $0.bundleIdentifier == tab.application.bundleIdentifier
            }
            targets.removeAll {
                $0.bundleIdentifier == tab.application.bundleIdentifier
            }
            targets.insert(
                target,
                at: min(insertionIndex ?? targets.endIndex, targets.endIndex)
            )
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

public struct SessionPlan: Codable, Equatable, Sendable {
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

public enum SessionInterruptionReason: String, Codable, Equatable, Sendable {
    case enforcementUnavailable
    case recoveryUnavailable
}

public struct InterruptedSession: Equatable, Sendable {
    public let plan: SessionPlan
    public let startedAt: Date
    public let interruptedAt: Date
    public let actualFocusDuration: TimeInterval
    public let reason: SessionInterruptionReason

    public init(
        plan: SessionPlan,
        startedAt: Date,
        interruptedAt: Date,
        actualFocusDuration: TimeInterval,
        reason: SessionInterruptionReason
    ) {
        self.plan = plan
        self.startedAt = startedAt
        self.interruptedAt = interruptedAt
        self.actualFocusDuration = actualFocusDuration
        self.reason = reason
    }
}

public struct RecoveringSession: Equatable, Sendable {
    public let activeSession: ActiveSession
    public let phase: SessionRecoveryPhase

    public init(
        activeSession: ActiveSession,
        phase: SessionRecoveryPhase
    ) {
        self.activeSession = activeSession
        self.phase = phase
    }
}

public enum SessionState: Equatable, Sendable {
    case idle
    case configuring(SessionDraft)
    case ready(SessionDraft)
    case starting(plan: SessionPlan, startsAt: Date)
    case recovering(RecoveringSession)
    case enforcing(ActiveSession)
    case resetPending(ResetPendingSession)
    case completed(CompletedSession)
    case endedEarly(EndedEarlySession)
    case interrupted(InterruptedSession)

    public var requiresControlledQuit: Bool {
        switch self {
        case .recovering, .enforcing, .resetPending:
            true
        case .idle, .configuring, .ready, .starting,
             .completed, .endedEarly, .interrupted:
            false
        }
    }
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

    public var hasPendingQuitRequest: Bool {
        isQuitPending
    }

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
    func resume(allowing targets: [SessionTarget]) throws
    func refresh() throws
    func stop()
}

public extension SessionEnforcing {
    func resume(allowing targets: [SessionTarget]) throws {
        try start(allowing: targets)
    }
}

@MainActor
public final class SessionEngine {
    public private(set) var state: SessionState = .idle
    public private(set) var didFailToRecordHistory = false

    private let clock: any SessionClock
    private let enforcement: CoordinatedSessionEnforcement
    private let recoveryStore: any SessionRecoveryPersisting
    private let historyStore: any SessionHistoryStoring

    public init(
        clock: any SessionClock,
        enforcement: any SessionEnforcing,
        tabActivationEnforcement: any TabActivationEnforcing = UnavailableTabActivationEnforcement(),
        recoveryStore: any SessionRecoveryPersisting = NoSessionRecoveryStore(),
        historyStore: any SessionHistoryStoring = NoSessionHistoryStore()
    ) {
        self.clock = clock
        self.enforcement = CoordinatedSessionEnforcement(
            applicationAndWindowEnforcement: enforcement,
            tabActivationEnforcement: tabActivationEnforcement
        )
        self.recoveryStore = recoveryStore
        self.historyStore = historyStore
    }

    public func beginConfiguration(duration: SessionDuration = .default) {
        switch state {
        case .idle, .completed, .endedEarly, .interrupted:
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
        try enforcement.preflight(targets: draft.targets)

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

        enforcement.stop()
        state = .ready(SessionDraft(duration: plan.duration, targets: plan.targets))
    }

    public func requestEarlyReset(countdown: TimeInterval = 30) throws {
        guard case let .enforcing(activeSession) = state else {
            throw SessionEngineError.invalidTransition
        }
        if hasCompleted(activeSession) {
            try completeNormally(activeSession)
            return
        }

        let pendingReset = ResetPendingSession(
            activeSession: activeSession,
            requestedAt: clock.now,
            confirmationAvailableAt: clock.now.addingTimeInterval(countdown),
            continuousConfirmationAvailableAt: clock.continuousNow + countdown
        )
        state = .resetPending(pendingReset)
        do {
            try recoveryStore.save(
                SessionRecoverySnapshot(pendingReset: pendingReset)
            )
        } catch {
            state = .enforcing(activeSession)
            throw error
        }
    }

    public func cancelEarlyReset() throws {
        guard case let .resetPending(pendingReset) = state else {
            throw SessionEngineError.invalidTransition
        }
        if hasCompleted(pendingReset.activeSession) {
            try completeNormally(pendingReset.activeSession)
            return
        }

        try recoveryStore.save(
            SessionRecoverySnapshot(activeSession: pendingReset.activeSession)
        )
        state = .enforcing(pendingReset.activeSession)
    }

    public func confirmEarlyReset() throws {
        guard case let .resetPending(pendingReset) = state else {
            throw SessionEngineError.invalidTransition
        }
        if hasCompleted(pendingReset.activeSession) {
            try completeNormally(pendingReset.activeSession)
            return
        }
        guard clock.continuousNow >= pendingReset.continuousConfirmationAvailableAt else {
            throw SessionEngineError.earlyResetConfirmationNotReady
        }

        do {
            try recoveryStore.clear()
        } catch {
            enforcement.stop()
            throw error
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
        recordHistory(for: activeSession, result: .endedEarly)
    }

    public func declineEarlyResetConfirmation() throws {
        guard case let .resetPending(pendingReset) = state else {
            throw SessionEngineError.invalidTransition
        }
        if hasCompleted(pendingReset.activeSession) {
            try completeNormally(pendingReset.activeSession)
            return
        }
        guard clock.continuousNow >= pendingReset.continuousConfirmationAvailableAt else {
            throw SessionEngineError.earlyResetConfirmationNotReady
        }

        try recoveryStore.save(
            SessionRecoverySnapshot(activeSession: pendingReset.activeSession)
        )
        state = .enforcing(pendingReset.activeSession)
    }

    public func advance() throws {
        switch state {
        case let .starting(plan, startsAt) where clock.now >= startsAt:
            do {
                guard try enforcement.start(allowing: plan.targets) == .active else {
                    return
                }
                let activeSession = ActiveSession(
                    plan: plan,
                    startedAt: clock.now,
                    endsAt: clock.now.addingTimeInterval(plan.duration.timeInterval),
                    continuousStartedAt: clock.continuousNow,
                    continuousEndsAt: clock.continuousNow + plan.duration.timeInterval
                )
                state = .enforcing(activeSession)
                do {
                    try recoveryStore.save(
                        SessionRecoverySnapshot(activeSession: activeSession)
                    )
                } catch {
                    enforcement.stop()
                    state = .ready(
                        SessionDraft(duration: plan.duration, targets: plan.targets)
                    )
                    throw error
                }
            } catch {
                enforcement.stop()
                state = .ready(SessionDraft(duration: plan.duration, targets: plan.targets))
                throw error
            }

        case let .recovering(recoveringSession):
            if hasCompleted(recoveringSession.activeSession) {
                try completeRecoveryWhileAwaiting(recoveringSession)
                return
            }
            do {
                guard try enforcement.resume(
                    allowing: recoveringSession.activeSession.plan.targets
                ) == .active else {
                    return
                }
                restoreRecoveredState(recoveringSession)
            } catch {
                try interruptFailedRecovery(
                    recoveringSession,
                    error: error
                )
            }

        case let .enforcing(activeSession) where hasCompleted(activeSession):
            try completeNormally(activeSession)

        case .enforcing:
            try enforcement.refresh()

        case let .resetPending(pendingReset)
            where hasCompleted(pendingReset.activeSession):
            try completeNormally(pendingReset.activeSession)

        case .resetPending:
            try enforcement.refresh()

        default:
            break
        }
    }

    public func reset() {
        if case .starting = state {
            enforcement.stop()
        } else if case .recovering = state {
            enforcement.restorePersistedState()
        } else if case .enforcing = state {
            enforcement.stop()
        } else if case .resetPending = state {
            enforcement.stop()
        }
        try? recoveryStore.clear()
        state = .idle
    }

    public func interrupt(reason: SessionInterruptionReason) throws {
        let activeSession: ActiveSession
        switch state {
        case let .enforcing(currentSession):
            activeSession = currentSession
        case let .resetPending(pendingReset):
            activeSession = pendingReset.activeSession
        default:
            throw SessionEngineError.invalidTransition
        }

        state = .interrupted(
            InterruptedSession(
                plan: activeSession.plan,
                startedAt: activeSession.startedAt,
                interruptedAt: clock.now,
                actualFocusDuration: max(
                    0,
                    clock.continuousNow - activeSession.continuousStartedAt
                ),
                reason: reason
            )
        )
        recordHistory(for: activeSession, result: .interrupted)
        do {
            try protectInterruptedSession()
        } catch {
            enforcement.stop()
            throw error
        }
        enforcement.stop()
    }

    @discardableResult
    public func recover() throws -> SessionRecoveryOutcome {
        guard let snapshot = try recoveryStore.load() else {
            return .none
        }
        let remaining = snapshot.endsAt.timeIntervalSince(clock.now)
        guard remaining > 0 else {
            try recoveryStore.clear()
            enforcement.restorePersistedState()
            state = .completed(
                CompletedSession(plan: snapshot.plan, completedAt: snapshot.endsAt)
            )
            recordHistory(
                SessionHistoryRecord(
                    startedAt: snapshot.startedAt,
                    plannedDuration: snapshot.plan.duration,
                    actualFocusTime: snapshot.plan.duration.timeInterval,
                    result: .completed
                )
            )
            return .completedWhileUnavailable
        }

        let elapsed = max(0, clock.now.timeIntervalSince(snapshot.startedAt))
        let activeSession = ActiveSession(
            plan: snapshot.plan,
            startedAt: snapshot.startedAt,
            endsAt: snapshot.endsAt,
            continuousStartedAt: clock.continuousNow - elapsed,
            continuousEndsAt: clock.continuousNow + remaining
        )
        let recoveringSession = RecoveringSession(
            activeSession: activeSession,
            phase: snapshot.phase
        )
        do {
            guard try enforcement.resume(allowing: snapshot.plan.targets)
                == .active
            else {
                state = .recovering(recoveringSession)
                return .awaitingEnforcement
            }
        } catch {
            try interruptFailedRecovery(recoveringSession, error: error)
        }
        restoreRecoveredState(recoveringSession)
        return .resumed
    }

    public func remainingTime() -> TimeInterval? {
        switch state {
        case let .starting(_, startsAt):
            max(0, startsAt.timeIntervalSince(clock.now))
        case let .recovering(recoveringSession):
            max(
                0,
                recoveringSession.activeSession.continuousEndsAt
                    - clock.continuousNow
            )
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

    private func completeNormally(_ activeSession: ActiveSession) throws {
        do {
            try recoveryStore.clear()
        } catch {
            enforcement.stop()
            throw error
        }
        enforcement.stop()
        state = .completed(
            CompletedSession(plan: activeSession.plan, completedAt: clock.now)
        )
        recordHistory(for: activeSession, result: .completed)
    }

    private func restoreRecoveredState(_ recoveringSession: RecoveringSession) {
        let activeSession = recoveringSession.activeSession
        switch recoveringSession.phase {
        case .enforcing:
            state = .enforcing(activeSession)
        case let .resetPending(requestedAt, confirmationAvailableAt):
            state = .resetPending(
                ResetPendingSession(
                    activeSession: activeSession,
                    requestedAt: requestedAt,
                    confirmationAvailableAt: confirmationAvailableAt,
                    continuousConfirmationAvailableAt: clock.continuousNow
                        + max(
                            0,
                            confirmationAvailableAt.timeIntervalSince(clock.now)
                        )
                )
            )
        }
    }

    private func interruptFailedRecovery(
        _ recoveringSession: RecoveringSession,
        error: Error
    ) throws -> Never {
        let activeSession = recoveringSession.activeSession
        let elapsed = min(
            activeSession.plan.duration.timeInterval,
            max(0, clock.now.timeIntervalSince(activeSession.startedAt))
        )
        state = .interrupted(
            InterruptedSession(
                plan: activeSession.plan,
                startedAt: activeSession.startedAt,
                interruptedAt: clock.now,
                actualFocusDuration: elapsed,
                reason: .recoveryUnavailable
            )
        )
        recordHistory(
            SessionHistoryRecord(
                startedAt: activeSession.startedAt,
                plannedDuration: activeSession.plan.duration,
                actualFocusTime: elapsed,
                result: .interrupted
            )
        )
        try? protectInterruptedSession()
        enforcement.restorePersistedState()
        throw error
    }

    private func completeRecoveryWhileAwaiting(
        _ recoveringSession: RecoveringSession
    ) throws {
        try recoveryStore.clear()
        enforcement.restorePersistedState()
        let activeSession = recoveringSession.activeSession
        state = .completed(
            CompletedSession(
                plan: activeSession.plan,
                completedAt: activeSession.endsAt
            )
        )
        recordHistory(
            SessionHistoryRecord(
                startedAt: activeSession.startedAt,
                plannedDuration: activeSession.plan.duration,
                actualFocusTime: activeSession.plan.duration.timeInterval,
                result: .completed
            )
        )
    }

    private func recordHistory(
        for activeSession: ActiveSession,
        result: SessionResult
    ) {
        recordHistory(
            SessionHistoryRecord(
                startedAt: activeSession.startedAt,
                plannedDuration: activeSession.plan.duration,
                actualFocusTime: clock.continuousNow
                    - activeSession.continuousStartedAt,
                result: result
            )
        )
    }

    private func recordHistory(_ record: SessionHistoryRecord) {
        didFailToRecordHistory = false
        do {
            try historyStore.record(record)
        } catch {
            didFailToRecordHistory = true
        }
    }

    private func protectInterruptedSession() throws {
        do {
            try recoveryStore.markInterrupted()
        } catch {
            try recoveryStore.clear()
            return
        }
        try? recoveryStore.clear()
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
