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
    @Published private(set) var applications: [RunningApplicationItem] = []
    @Published private(set) var selectedApplicationIDs: Set<String> = []
    @Published var durationSeconds: Int
    @Published private(set) var durationValidationMessage: String?
    @Published private(set) var accessibilityAuthorized = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var shouldExplainAccessibility = true
    @Published var isReviewing = false
    @Published private(set) var remainingTime: TimeInterval = 0
    @Published private(set) var earlyResetRemainingTime: TimeInterval = 0
    @Published private(set) var notice: String?

    private let defaults: UserDefaults
    private let permissionClient: AccessibilityPermissionClient
    private let applicationCatalog: RunningApplicationCatalog
    private let enforcement: ApplicationEnforcementController
    private let engine: SessionEngine
    private var lastPermissionCheck = Date.distantPast
    private var noticeTask: Task<Void, Never>?
    private var timer: Timer?
    private var quitCoordinator = QuitCoordinator()
    private var addedApplicationIDs: Set<String> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        permissionClient = AccessibilityPermissionClient()
        applicationCatalog = RunningApplicationCatalog()
        enforcement = ApplicationEnforcementController(permissionClient: permissionClient)
        engine = SessionEngine(clock: SystemSessionClock(), enforcement: enforcement)

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

        engine.beginConfiguration(duration: initialDuration)
        synchronizeWithEngine()
        refreshAccessibilityStatus()
        shouldExplainAccessibility = !defaults.bool(forKey: Self.accessibilityIntroKey)
            || !accessibilityGranted
        refreshApplications()

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

    var selectedApplications: [RunningApplicationItem] {
        applications.filter { selectedApplicationIDs.contains($0.id) }
    }

    var canReview: Bool {
        accessibilityGranted
            && !selectedApplicationIDs.isEmpty
            && selectedApplications.allSatisfy(\.isAvailable)
            && SessionDuration(seconds: durationSeconds) != nil
    }

    var formattedDuration: String {
        Self.format(seconds: durationSeconds)
    }

    var formattedRemainingTime: String {
        Self.format(seconds: max(0, Int(remainingTime.rounded(.up))))
    }

    var countdownNumber: Int {
        max(1, Int(remainingTime.rounded(.up)))
    }

    var earlyResetCountdownNumber: Int {
        max(0, Int(earlyResetRemainingTime.rounded(.up)))
    }

    var formattedEarlyResetRemainingTime: String {
        Self.format(seconds: earlyResetCountdownNumber)
    }

    var isEarlyResetConfirmationAvailable: Bool {
        engine.isEarlyResetConfirmationAvailable
    }

    var isActiveSession: Bool {
        switch state {
        case .enforcing, .resetPending:
            true
        default:
            false
        }
    }

    var menuBarTitle: String {
        if case .enforcing = state {
            if let notice {
                return "\(notice) · \(formattedRemainingTime)"
            }
            return formattedRemainingTime
        }
        if case .resetPending = state {
            return "Reset \(formattedEarlyResetRemainingTime) · \(formattedRemainingTime)"
        }
        return "StayPane"
    }

    func refreshApplications() {
        let previousApplications = Dictionary(
            uniqueKeysWithValues: applications.map { ($0.id, $0) }
        )
        var refreshedApplications = Dictionary(
            uniqueKeysWithValues: applicationCatalog.load().map { ($0.id, $0) }
        )
        let retainedApplicationIDs = selectedApplicationIDs.union(addedApplicationIDs)

        for id in retainedApplicationIDs where refreshedApplications[id] == nil {
            guard let previousApplication = previousApplications[id] else {
                continue
            }

            if let applicationURL = previousApplication.target.applicationURL,
               let refreshedApplication = try? applicationCatalog.loadApplication(
                   at: applicationURL
               )
            {
                refreshedApplications[id] = refreshedApplication
            } else {
                refreshedApplications[id] = previousApplication.asUnavailable()
            }
        }

        applications = refreshedApplications.values.sorted {
            $0.target.displayName.localizedCaseInsensitiveCompare($1.target.displayName)
                == .orderedAscending
        }

        for application in selectedApplications {
            engine.select(target: application.target)
        }
        synchronizeWithEngine()
    }

    func setApplication(id: String, isSelected: Bool) {
        guard let application = applications.first(where: { $0.id == id }) else {
            return
        }

        if isSelected {
            selectedApplicationIDs.insert(id)
            engine.select(target: application.target)
        } else {
            selectedApplicationIDs.remove(id)
            engine.deselectTarget(bundleIdentifier: application.target.bundleIdentifier)
        }
        synchronizeWithEngine()
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

        guard accessibilityGranted else {
            showNotice("Grant Accessibility access before starting a session.")
            return
        }
        guard !selectedApplications.isEmpty else {
            showNotice("Choose at least one application to allow.")
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
        selectedApplicationIDs = []
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
        }

        do {
            try engine.advance()
        } catch {
            isReviewing = false
            showNotice(error.localizedDescription)
        }
        synchronizeWithEngine()
        terminateIfQuitRequestFinished()
    }

    func prepareToQuit() {
        stopForTermination()
    }

    func prepareForSystemTermination() {
        stopForTermination()
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
            return format(seconds: seconds)
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
        state = engine.state
        remainingTime = engine.remainingTime() ?? 0
        earlyResetRemainingTime = engine.earlyResetRemainingTime() ?? 0
    }

    private func failOpen(after error: Error) {
        engine.reset()
        selectedApplicationIDs = []
        isReviewing = false
        quitCoordinator.cancelDeferredQuit()
        engine.beginConfiguration(duration: currentValidDuration())
        synchronizeWithEngine()
        showNotice("Enforcement stopped safely: \(error.localizedDescription)")
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

    private static func format(seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3_600
        let minutes = (safeSeconds % 3_600) / 60
        let seconds = safeSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
