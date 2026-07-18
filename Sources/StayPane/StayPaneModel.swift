import AppKit
import Combine
import Foundation
import StayPaneCore
import UniformTypeIdentifiers

@MainActor
final class StayPaneModel: NSObject, ObservableObject, StayPaneTerminationHandling {
    static let lastDurationKey = "lastSessionDurationSeconds"
    static let accessibilityIntroKey = "hasSeenAccessibilityIntro"

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var applications: [ApplicationCatalogItem] = []
    @Published private(set) var windowsByApplicationID: [
        String: [WindowTarget]
    ] = [:]
    @Published private(set) var selectedTargetIDs: Set<TargetIdentifier> = []
    @Published var expandedApplicationIDs: Set<String> = []
    @Published var durationSeconds: Int
    @Published private(set) var durationValidationMessage: String?
    @Published private(set) var accessibilityAuthorized = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var shouldExplainAccessibility = true
    @Published var isReviewing = false
    @Published private(set) var remainingTime: TimeInterval = 0
    @Published private(set) var earlyResetRemainingTime: TimeInterval = 0
    @Published private(set) var notice: String?
    @Published private var transientSessionPresence: SessionPresence?

    private let defaults: UserDefaults
    private let permissionClient: AccessibilityPermissionClient
    private let applicationCatalog: ApplicationCatalog
    private let windowCatalog: AccessibilityWindowCatalog
    private let outlineController: WindowOutlineController
    private let enforcement: ApplicationEnforcementController
    private let engine: SessionEngine
    private var lastPermissionCheck = Date.distantPast
    private var noticeTask: Task<Void, Never>?
    private var sessionPresenceTask: Task<Void, Never>?
    private var timer: Timer?
    private var quitCoordinator = QuitCoordinator()
    private var addedApplicationIDs: Set<String> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        permissionClient = AccessibilityPermissionClient()
        applicationCatalog = ApplicationCatalog()
        let windowCatalog = AccessibilityWindowCatalog()
        self.windowCatalog = windowCatalog
        outlineController = WindowOutlineController()
        enforcement = ApplicationEnforcementController(
            permissionClient: permissionClient,
            availabilityResolver: applicationCatalog,
            windowCatalog: windowCatalog
        )
        let sessionRecoveryStore = FileSessionRecoveryStore()
        engine = SessionEngine(
            clock: SystemSessionClock(),
            enforcement: enforcement,
            recoveryStore: sessionRecoveryStore
        )

        let storedDuration = defaults.integer(forKey: Self.lastDurationKey)
        let initialDuration = SessionDuration(seconds: storedDuration) ?? .default
        durationSeconds = initialDuration.seconds

        super.init()

        enforcement.onBlockedApplication = { [weak self] message in
            self?.showNotice(message)
        }
        enforcement.onEnforcementFailure = { [weak self] error in
            self?.failOpen(after: error)
        }
        enforcement.onRestorationFailure = { [weak self] count in
            self?.showNotice(
                "\(count) window(s) could not be restored yet. StayPane will keep retrying."
            )
        }
        enforcement.onRestorationRecovered = { [weak self] in
            self?.showNotice("No pending window restorations remain.")
        }

        let startupNotice: String?
        do {
            switch try engine.recover() {
            case .none:
                enforcement.stop()
                engine.beginConfiguration(duration: initialDuration)
                startupNotice = nil
            case .resumed:
                startupNotice = "StayPane resumed the unfinished Session from its Fixed End Time."
            case .completedWhileUnavailable:
                startupNotice = "The Session ended while StayPane was unavailable. Restoration cleanup is complete."
            }
        } catch {
            if case .interrupted = engine.state {
                startupNotice = "The saved Session could not be resumed safely and was marked Interrupted."
            } else {
                try? sessionRecoveryStore.clear()
                enforcement.stop()
                engine.beginConfiguration(duration: initialDuration)
                startupNotice = "StayPane discarded unreadable Recovery data and performed Restoration for what remained controllable."
            }
        }
        durationSeconds = durationFromEngine()
        synchronizeWithEngine()
        refreshAccessibilityStatus()
        shouldExplainAccessibility = !defaults.bool(forKey: Self.accessibilityIntroKey)
            || !accessibilityGranted
        refreshApplications()
        if let startupNotice {
            showNotice(startupNotice)
        }

        let timer = Timer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(timerDidFire),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    var selectedApplications: [ApplicationCatalogItem] {
        applications.filter { selectedApplicationIDs.contains($0.id) }
    }

    var selectedApplicationIDs: Set<String> {
        Set(selectedTargetIDs.compactMap { identifier in
            guard case let .application(bundleIdentifier) = identifier else {
                return nil
            }
            return bundleIdentifier
        })
    }

    var selectedWindowIDs: Set<WindowIdentifier> {
        Set(selectedTargetIDs.compactMap { identifier in
            guard case let .window(windowIdentifier) = identifier else {
                return nil
            }
            return windowIdentifier
        })
    }

    var configuredTargets: [SessionTarget] {
        switch engine.state {
        case let .configuring(draft), let .ready(draft):
            draft.targets
        default:
            []
        }
    }

    var canReview: Bool {
        accessibilityGranted
            && !selectedTargetIDs.isEmpty
            && selectedApplications.allSatisfy(\.isAvailable)
            && SessionDuration(seconds: durationSeconds) != nil
    }

    var formattedDuration: String {
        formatSessionTime(seconds: durationSeconds)
    }

    var formattedRemainingTime: String {
        formatSessionTime(seconds: max(0, Int(remainingTime.rounded(.up))))
    }

    var countdownNumber: Int {
        max(1, Int(remainingTime.rounded(.up)))
    }

    var earlyResetCountdownNumber: Int {
        max(0, Int(earlyResetRemainingTime.rounded(.up)))
    }

    var formattedEarlyResetRemainingTime: String {
        formatSessionTime(seconds: earlyResetCountdownNumber)
    }

    var isEarlyResetConfirmationAvailable: Bool {
        engine.isEarlyResetConfirmationAvailable
    }

    var isActiveSession: Bool {
        sessionPresence.isEnforcing
    }

    var sessionPresence: SessionPresence {
        switch state {
        case .enforcing:
            .active(remainingSeconds: roundedUpSeconds(remainingTime))
        case .resetPending:
            .resetPending(
                focusRemainingSeconds: roundedUpSeconds(remainingTime),
                resetRemainingSeconds: roundedUpSeconds(earlyResetRemainingTime)
            )
        default:
            transientSessionPresence ?? .inactive
        }
    }

    var menuBarTitle: String {
        sessionPresence.menuBarTitle
    }

    func refreshApplications() {
        let previousApplications = Dictionary(
            uniqueKeysWithValues: applications.map { ($0.id, $0) }
        )
        var refreshedApplications = Dictionary(
            uniqueKeysWithValues: applicationCatalog.load().map { ($0.id, $0) }
        )
        let retainedApplicationIDs = Set(
            configuredTargets.map(\.bundleIdentifier)
        ).union(addedApplicationIDs)

        for id in retainedApplicationIDs where refreshedApplications[id] == nil {
            guard let previousApplication = previousApplications[id] else {
                continue
            }

            refreshedApplications[id] = applicationCatalog.refresh(previousApplication)
        }

        applications = refreshedApplications.values.sorted {
            $0.target.displayName.localizedCaseInsensitiveCompare($1.target.displayName)
                == .orderedAscending
        }

        for target in configuredTargets {
            guard case let .application(applicationTarget) = target,
                  let application = applications.first(where: {
                      $0.id == applicationTarget.bundleIdentifier
                  })
            else {
                continue
            }
            engine.select(target: .application(application.target))
        }

        let applicationIDsWithWindowLists = expandedApplicationIDs.union(
            configuredTargets.compactMap { target in
                guard case let .window(window) = target else {
                    return nil
                }
                return window.application.bundleIdentifier
            }
        )
        for applicationID in applicationIDsWithWindowLists {
            refreshWindows(for: applicationID)
        }
        synchronizeWithEngine()
    }

    func setApplication(id: String, isSelected: Bool) {
        guard let application = applications.first(where: { $0.id == id }) else {
            return
        }

        if isSelected {
            engine.select(target: .application(application.target))
        } else {
            engine.deselectTarget(.application(bundleIdentifier: id))
        }
        synchronizeWithEngine()
    }

    func setWindow(id: WindowIdentifier, isSelected: Bool) {
        guard let window = windowsByApplicationID.values
            .joined()
            .first(where: { $0.id == id })
        else {
            return
        }

        if isSelected {
            engine.select(target: SessionTarget.window(window))
        } else {
            engine.deselectTarget(.window(id))
        }
        synchronizeWithEngine()
    }

    func setApplicationExpanded(id: String, isExpanded: Bool) {
        if isExpanded {
            expandedApplicationIDs.insert(id)
            refreshWindows(for: id)
        } else {
            expandedApplicationIDs.remove(id)
            outlineController.hide()
        }
    }

    func windows(for applicationID: String) -> [WindowTarget] {
        windowsByApplicationID[applicationID] ?? []
    }

    func highlightWindow(id: WindowIdentifier, isHighlighted: Bool) {
        guard isHighlighted else {
            outlineController.hide()
            return
        }

        if let window = windowsByApplicationID.values
            .joined()
            .first(where: { $0.id == id })
        {
            _ = try? windowCatalog.loadWindows(for: window.application)
        }
        guard let frame = windowCatalog.frame(for: id) else {
            outlineController.hide()
            return
        }
        outlineController.show(around: frame)
    }

    func refreshWindows(for applicationID: String) {
        guard
            let application = applications.first(where: { $0.id == applicationID }),
            application.isRunning
        else {
            windowsByApplicationID[applicationID] = []
            return
        }

        do {
            let windows = try windowCatalog.loadWindows(for: application.target)
            windowsByApplicationID[applicationID] = windows
            removeClosedWindowSelections(
                for: applicationID,
                availableWindowIDs: Set(windows.map(\.id))
            )
        } catch {
            windowsByApplicationID[applicationID] = []
            showNotice(error.localizedDescription)
        }
    }

    func addInstalledApplication() {
        let panel = NSOpenPanel()
        panel.title = "Add an Installed Application"
        panel.message = "Choose an application to allow during this session."
        panel.prompt = "Add Application"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let applicationURL = panel.url else {
            return
        }

        do {
            let application = try applicationCatalog.loadApplication(at: applicationURL)
            addedApplicationIDs.insert(application.id)
            applications.removeAll { $0.id == application.id }
            applications.append(application)
            applications.sort {
                $0.target.displayName.localizedCaseInsensitiveCompare($1.target.displayName)
                    == .orderedAscending
            }
            setApplication(id: application.id, isSelected: true)
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    func updateDuration() {
        guard let duration = SessionDuration(seconds: durationSeconds) else {
            durationValidationMessage = "Enter 10 seconds to 24 hours (86,400 seconds)."
            return
        }

        do {
            try engine.setDuration(duration)
            durationValidationMessage = nil
            defaults.set(duration.seconds, forKey: Self.lastDurationKey)
            synchronizeWithEngine()
        } catch {
            durationSeconds = durationFromEngine()
            durationValidationMessage = nil
            showNotice("The duration is locked for the current session.")
        }
    }

    func resetDurationToDefault() {
        durationSeconds = SessionDuration.default.seconds
        updateDuration()
    }

    func requestAccessibilityAccess() {
        defaults.set(true, forKey: Self.accessibilityIntroKey)
        shouldExplainAccessibility = true
        permissionClient.requestAccess()
        permissionClient.openSystemSettings()
        refreshAccessibilityStatus()
    }

    func refreshAccessibilityStatus(forceVerification: Bool = true) {
        accessibilityAuthorized = permissionClient.isGranted
        guard accessibilityAuthorized else {
            accessibilityGranted = false
            return
        }

        if forceVerification || !accessibilityGranted {
            accessibilityGranted = permissionClient.verifyWindowControl()
        }
        if accessibilityGranted {
            shouldExplainAccessibility = false
        }
    }

    func beginReview() {
        refreshAccessibilityStatus()
        updateDuration()
        refreshApplications()

        guard accessibilityGranted else {
            showNotice("Grant Accessibility access before starting a session.")
            return
        }
        guard !configuredTargets.isEmpty else {
            showNotice("Choose at least one application or window to allow.")
            return
        }
        let unavailableApplications = selectedApplications.filter { !$0.isAvailable }
        guard unavailableApplications.isEmpty else {
            showNotice(
                "Remove or reinstall unavailable targets: "
                    + unavailableApplications.map(\.target.displayName).joined(separator: ", ")
            )
            return
        }
        let unavailableWindows = windowCatalog.unavailableWindowTargets(
            in: configuredTargets
        )
        guard unavailableWindows.isEmpty else {
            showNotice(
                "Choose reopened versions of these closed windows: "
                    + unavailableWindows.map(\.title).joined(separator: ", ")
            )
            return
        }
        guard durationValidationMessage == nil else {
            return
        }

        isReviewing = true
    }

    func startCountdown() {
        refreshAccessibilityStatus()
        guard accessibilityGranted else {
            isReviewing = false
            showNotice("Accessibility access is missing, so the session was not started.")
            return
        }

        do {
            outlineController.hide()
            try engine.beginStartCountdown()
            isReviewing = false
            synchronizeWithEngine()
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    func cancelCountdown() {
        do {
            try engine.cancelStartCountdown()
            synchronizeWithEngine()
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    func requestEarlyReset() {
        if case .resetPending = state {
            return
        }

        do {
            try engine.requestEarlyReset()
            synchronizeWithEngine()
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    func cancelEarlyReset() {
        do {
            try engine.cancelEarlyReset()
            quitCoordinator.cancelDeferredQuit()
            synchronizeWithEngine()
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    func declineEarlyResetConfirmation() {
        do {
            try engine.declineEarlyResetConfirmation()
            quitCoordinator.cancelDeferredQuit()
            synchronizeWithEngine()
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    func confirmEarlyReset() {
        do {
            try engine.confirmEarlyReset()
            synchronizeWithEngine()
            terminateIfQuitRequestFinished()
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    func handleQuitRequest() -> Bool {
        let decision = quitCoordinator.requestQuit(
            isSessionActive: isActiveSession,
            pendingRestorationCount: enforcement.pendingRestorationCount
        )

        switch decision {
        case .terminateNow:
            prepareToQuit()
            return true

        case .waitForRestoration:
            showNotice("StayPane is still restoring windows and will quit when restoration finishes.")
            return false

        case .beginEarlyReset:
            requestEarlyReset()
            NSApplication.shared.activate(ignoringOtherApps: true)
            return false
        }
    }

    func startAnotherSession() {
        engine.beginConfiguration(duration: currentValidDuration())
        selectedTargetIDs = []
        isReviewing = false
        quitCoordinator.cancelDeferredQuit()
        synchronizeWithEngine()
        refreshApplications()
    }

    func tick() {
        if Date().timeIntervalSince(lastPermissionCheck) >= 1 {
            lastPermissionCheck = Date()
            refreshAccessibilityStatus(forceVerification: false)
            enforcement.retryPendingRestorations()
            refreshExpandedWindowListsIfEditable()
        }

        let wasActive = isActiveSession
        do {
            try engine.advance()
        } catch {
            if wasActive {
                failOpen(after: error)
                return
            }
            isReviewing = false
            refreshApplications()
            showNotice(error.localizedDescription)
        }
        synchronizeWithEngine()
        terminateIfQuitRequestFinished()
    }

    func prepareToQuit() {
        stopForTermination()
    }

    func prepareForSystemTermination() {
        quitCoordinator.cancelDeferredQuit()
        enforcement.suspendForSystemTermination()
        timer?.invalidate()
    }

    private func stopForTermination() {
        quitCoordinator.cancelDeferredQuit()
        engine.reset()
        timer?.invalidate()
    }

    func showNotice(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else {
                return
            }
            self?.notice = nil
        }
    }

    static func formatPreset(seconds: Int) -> String {
        guard seconds >= 60 else {
            return "\(seconds)s"
        }

        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60

        if remainder > 0 {
            return formatSessionTime(seconds: seconds)
        }
        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }

    private func synchronizeWithEngine() {
        let previousState = state
        let nextState = engine.state
        state = nextState
        updateTransientSessionPresence(from: previousState, to: nextState)
        remainingTime = engine.remainingTime() ?? 0
        earlyResetRemainingTime = engine.earlyResetRemainingTime() ?? 0
        switch state {
        case let .configuring(draft), let .ready(draft):
            selectedTargetIDs = Set(draft.targets.map(\.id))
        case let .starting(plan, _):
            selectedTargetIDs = Set(plan.targets.map(\.id))
        case let .enforcing(activeSession):
            selectedTargetIDs = Set(activeSession.plan.targets.map(\.id))
        case let .resetPending(pendingReset):
            selectedTargetIDs = Set(pendingReset.activeSession.plan.targets.map(\.id))
        case .idle, .completed, .endedEarly, .interrupted:
            selectedTargetIDs = []
        }
    }

    private func failOpen(after error: Error) {
        do {
            try engine.interrupt(reason: .enforcementUnavailable)
        } catch {
            enforcement.stop()
        }
        selectedTargetIDs = []
        outlineController.hide()
        isReviewing = false
        quitCoordinator.cancelDeferredQuit()
        synchronizeWithEngine()
        showNotice(
            "Session Interrupted. StayPane used Fail Open and performed Restoration for what remained controllable: \(error.localizedDescription)"
        )
    }

    private func refreshExpandedWindowListsIfEditable() {
        switch engine.state {
        case .configuring, .ready:
            for applicationID in expandedApplicationIDs {
                refreshWindows(for: applicationID)
            }
        default:
            break
        }
    }

    private func removeClosedWindowSelections(
        for bundleIdentifier: String,
        availableWindowIDs: Set<WindowIdentifier>
    ) {
        switch engine.state {
        case .configuring, .ready:
            removeClosedWindowSelectionsFromEditableDraft(
                bundleIdentifier: bundleIdentifier,
                availableWindowIDs: availableWindowIDs
            )
        default:
            return
        }
    }

    private func removeClosedWindowSelectionsFromEditableDraft(
        bundleIdentifier: String,
        availableWindowIDs: Set<WindowIdentifier>
    ) {
        let closedWindows = configuredTargets.compactMap { target -> WindowTarget? in
            guard case let .window(window) = target,
                  window.application.bundleIdentifier == bundleIdentifier,
                  !availableWindowIDs.contains(window.id)
            else {
                return nil
            }
            return window
        }
        for window in closedWindows {
            engine.deselectTarget(.window(window.id))
        }
        if !closedWindows.isEmpty {
            synchronizeWithEngine()
            showNotice(
                "Closed window selections were removed: "
                    + closedWindows.map(\.title).joined(separator: ", ")
            )
        }
    }

    private func terminateIfQuitRequestFinished() {
        guard quitCoordinator.consumeQuitWhenSafe(
            isSessionActive: isActiveSession,
            pendingRestorationCount: enforcement.pendingRestorationCount
        ) else {
            return
        }

        timer?.invalidate()
        NSApplication.shared.terminate(nil)
    }

    private func durationFromEngine() -> Int {
        switch engine.state {
        case let .configuring(draft), let .ready(draft):
            draft.duration.seconds
        case let .starting(plan, _):
            plan.duration.seconds
        case let .enforcing(activeSession):
            activeSession.plan.duration.seconds
        case let .resetPending(pendingReset):
            pendingReset.activeSession.plan.duration.seconds
        case let .completed(completedSession):
            completedSession.plan.duration.seconds
        case let .endedEarly(endedSession):
            endedSession.plan.duration.seconds
        case let .interrupted(interruptedSession):
            interruptedSession.plan.duration.seconds
        case .idle:
            currentValidDuration().seconds
        }
    }

    @objc
    private func timerDidFire() {
        tick()
    }

    private func currentValidDuration() -> SessionDuration {
        SessionDuration(seconds: durationSeconds) ?? .default
    }

    private func roundedUpSeconds(_ timeInterval: TimeInterval) -> Int {
        max(0, Int(timeInterval.rounded(.up)))
    }

    private func updateTransientSessionPresence(
        from previousState: SessionState,
        to nextState: SessionState
    ) {
        let presence: SessionPresence
        switch nextState {
        case .completed:
            guard case .completed = previousState else {
                presence = .completed
                break
            }
            return
        case .endedEarly:
            guard case .endedEarly = previousState else {
                presence = .endedEarly
                break
            }
            return
        case .interrupted:
            guard case .interrupted = previousState else {
                presence = .interrupted
                break
            }
            return
        default:
            sessionPresenceTask?.cancel()
            transientSessionPresence = nil
            return
        }

        transientSessionPresence = presence
        sessionPresenceTask?.cancel()
        sessionPresenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else {
                return
            }
            self?.transientSessionPresence = nil
        }
    }
}
