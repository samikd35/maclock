import Combine
import Foundation
import StayPaneCore

@MainActor
final class StayPaneModel: NSObject, ObservableObject {
    static let lastDurationKey = "lastSessionDurationSeconds"
    static let accessibilityIntroKey = "hasSeenAccessibilityIntro"

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var applications: [RunningApplicationItem] = []
    @Published var selectedApplicationID: String?
    @Published var durationSeconds: Int
    @Published private(set) var durationValidationMessage: String?
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var shouldExplainAccessibility = true
    @Published var isReviewing = false
    @Published private(set) var remainingTime: TimeInterval = 0
    @Published private(set) var notice: String?

    private let defaults: UserDefaults
    private let permissionClient: AccessibilityPermissionClient
    private let applicationCatalog: RunningApplicationCatalog
    private let enforcement: ApplicationEnforcementController
    private let engine: SessionEngine
    private var lastPermissionCheck = Date.distantPast
    private var noticeTask: Task<Void, Never>?
    private var timer: Timer?

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

    var selectedApplication: RunningApplicationItem? {
        applications.first { $0.id == selectedApplicationID }
    }

    var canReview: Bool {
        accessibilityGranted
            && selectedApplication != nil
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

    var menuBarTitle: String {
        if case let .enforcing(activeSession) = state {
            if notice != nil {
                return "Blocked · \(activeSession.plan.target.displayName) only"
            }
            return formattedRemainingTime
        }
        return "StayPane"
    }

    func refreshApplications() {
        applications = applicationCatalog.load()

        if let selectedApplicationID,
           !applications.contains(where: { $0.id == selectedApplicationID })
        {
            self.selectedApplicationID = nil
            engine.clearTarget()
            synchronizeWithEngine()
        }
    }

    func chooseApplication(id: String?) {
        selectedApplicationID = id

        guard
            let id,
            let application = applications.first(where: { $0.id == id })
        else {
            engine.clearTarget()
            synchronizeWithEngine()
            return
        }

        engine.select(target: application.target)
        synchronizeWithEngine()
    }

    func updateDuration() {
        guard let duration = SessionDuration(seconds: durationSeconds) else {
            durationValidationMessage = "Enter 10 seconds to 24 hours (86,400 seconds)."
            return
        }

        durationValidationMessage = nil
        defaults.set(duration.seconds, forKey: Self.lastDurationKey)
        try? engine.setDuration(duration)
        synchronizeWithEngine()
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

    func refreshAccessibilityStatus() {
        accessibilityGranted = permissionClient.isGranted
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
        guard selectedApplication != nil else {
            showNotice("Choose one running application to allow.")
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

    func startAnotherSession() {
        engine.beginConfiguration(duration: currentValidDuration())
        selectedApplicationID = nil
        isReviewing = false
        synchronizeWithEngine()
        refreshApplications()
    }

    func tick() {
        if Date().timeIntervalSince(lastPermissionCheck) >= 1 {
            lastPermissionCheck = Date()
            refreshAccessibilityStatus()
        }

        do {
            try engine.advance()
        } catch {
            isReviewing = false
            showNotice(error.localizedDescription)
        }
        synchronizeWithEngine()
    }

    func prepareToQuit() {
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
