import AppKit
import ApplicationServices
import StayPaneCore
import StayPanePlatform

enum ApplicationEnforcementError: LocalizedError, Equatable {
    case accessibilityPermissionMissing
    case windowControlUnavailable(String)
    case allowedApplicationsUnavailable([String])
    case allowedWindowsUnavailable([String])
    case windowRestorationPending(Int)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "Accessibility access is required before StayPane can start a session."
        case let .windowControlUnavailable(applicationName):
            "StayPane could not safely control \(applicationName)."
        case let .allowedApplicationsUnavailable(applicationNames):
            "These allowed applications are no longer installed: \(applicationNames.joined(separator: ", ")). Remove them or install them again before starting."
        case let .allowedWindowsUnavailable(windowTitles):
            "These allowed windows closed before the session started: \(windowTitles.joined(separator: ", ")). Choose their reopened windows again."
        case let .windowRestorationPending(count):
            "StayPane is still restoring \(count) window(s) from the previous session."
        }
    }
}

@MainActor
final class ApplicationEnforcementController: NSObject, SessionEnforcing {
    var onBlockedApplication: ((String) -> Void)?
    var onEnforcementFailure: ((Error) -> Void)?
    var onRestorationFailure: ((Int) -> Void)?
    var onRestorationRecovered: (() -> Void)?

    var pendingRestorationCount: Int {
        restorationTracker.pendingCount
    }

    private let permissionClient: any AccessibilityPermissionChecking
    private let availabilityResolver: any ApplicationAvailabilityResolving
    private let windowCatalog: AccessibilityWindowCatalog
    private let notificationCenter: NotificationCenter
    private let windowOperator: any AccessibilityWindowOperating
    private let restorationTracker: WindowRestorationTracker
    private var allowedTargets: [SessionTarget] = []
    private var windowPolicy = WindowAllowlistPolicy(targets: [])
    private var isObserving = false
    private var lastNoticeUptime: TimeInterval = -.infinity
    private var lastFullScanUptime: TimeInterval = -.infinity

    private static let fullScanInterval: TimeInterval = 0.25

    init(
        permissionClient: any AccessibilityPermissionChecking,
        availabilityResolver: any ApplicationAvailabilityResolving,
        windowCatalog: AccessibilityWindowCatalog = AccessibilityWindowCatalog(),
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        windowOperator: any AccessibilityWindowOperating = SystemAccessibilityWindowOperator()
    ) {
        self.permissionClient = permissionClient
        self.availabilityResolver = availabilityResolver
        self.windowCatalog = windowCatalog
        self.notificationCenter = notificationCenter
        self.windowOperator = windowOperator
        restorationTracker = WindowRestorationTracker(operatorClient: windowOperator)
        super.init()
    }

    func start(allowing targets: [SessionTarget]) throws {
        let applicationTargets = targets.compactMap { target -> ApplicationTarget? in
            guard case let .application(application) = target else {
                return nil
            }
            return application
        }
        let unavailableApplications = applicationTargets.filter {
            !availabilityResolver.isAvailable($0)
        }
        guard unavailableApplications.isEmpty else {
            throw ApplicationEnforcementError.allowedApplicationsUnavailable(
                unavailableApplications.map(\.displayName)
            )
        }
        guard permissionClient.isGranted, permissionClient.verifyWindowControl() else {
            throw ApplicationEnforcementError.accessibilityPermissionMissing
        }

        let unavailableWindows = windowCatalog.unavailableWindowTargets(in: targets)
        guard unavailableWindows.isEmpty else {
            throw ApplicationEnforcementError.allowedWindowsUnavailable(
                unavailableWindows.map(\.title)
            )
        }
        if restorationTracker.pendingCount > 0 {
            let outcome = restorationTracker.restorePendingWindows()
            guard outcome.pendingCount == 0 else {
                throw ApplicationEnforcementError.windowRestorationPending(
                    outcome.pendingCount
                )
            }
        }

        allowedTargets = targets
        windowPolicy = WindowAllowlistPolicy(targets: targets)
        beginObservingActivations()

        do {
            try enforceCurrentWindows()
            activateInitialAllowedTarget()
        } catch {
            stop()
            if pendingRestorationCount > 0 {
                throw ApplicationEnforcementError.windowRestorationPending(
                    pendingRestorationCount
                )
            }
            throw error
        }
    }

    func refresh() throws {
        guard !allowedTargets.isEmpty else {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFullScanUptime >= Self.fullScanInterval else {
            return
        }
        guard permissionClient.isGranted else {
            throw ApplicationEnforcementError.accessibilityPermissionMissing
        }
        try enforceCurrentWindows()
    }

    func stop() {
        endObservingActivations()
        allowedTargets = []
        windowPolicy = WindowAllowlistPolicy(targets: [])
        lastFullScanUptime = -.infinity

        let outcome = restorationTracker.restorePendingWindows()
        if outcome.pendingCount > 0 {
            onRestorationFailure?(outcome.pendingCount)
        }
    }

    func retryPendingRestorations() {
        guard allowedTargets.isEmpty, restorationTracker.pendingCount > 0 else {
            return
        }

        let outcome = restorationTracker.restorePendingWindows()
        if outcome.pendingCount == 0 {
            onRestorationRecovered?()
        }
    }

    @objc
    private func applicationDidActivate(_ notification: Notification) {
        guard
            !allowedTargets.isEmpty,
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            application.activationPolicy == .regular,
            let bundleIdentifier = application.bundleIdentifier,
            !AccessibilityWindowCatalog.isEssentialSystemApplication(
                bundleIdentifier: bundleIdentifier
            )
        else {
            return
        }

        do {
            let applicationTarget = makeApplicationTarget(application)
            let windows = try windowCatalog.catalogueWindows(for: applicationTarget)
            try enforce(windows: windows, applicationName: applicationTarget.displayName)

            guard let focusedWindow = windows.first(where: \.isFocused) else {
                if !allowedTargets.contains(where: {
                    if case let .application(target) = $0 {
                        return target.bundleIdentifier == bundleIdentifier
                    }
                    return false
                }) {
                    restoreAllowedFocus(preferredTarget: nil)
                    publishBlockedNotice(
                        "\(applicationTarget.displayName) is outside this focus session."
                    )
                }
                return
            }

            let decision = windowPolicy.handleActivation(focusedWindow.observation)
            guard case let .block(refocusTarget) = decision else {
                return
            }

            restoreAllowedFocus(preferredTarget: refocusTarget)
            publishBlockedNotice(
                "\(focusedWindow.target.title) is outside this focus session."
            )
        } catch {
            NSApplication.shared.activate(ignoringOtherApps: true)
            stop()
            let reportedError: Error = pendingRestorationCount > 0
                ? ApplicationEnforcementError.windowRestorationPending(
                    pendingRestorationCount
                )
                : error
            onEnforcementFailure?(reportedError)
        }
    }

    private func beginObservingActivations() {
        guard !isObserving else {
            return
        }

        notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        isObserving = true
    }

    private func endObservingActivations() {
        guard isObserving else {
            return
        }

        notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        isObserving = false
    }

    private func enforceCurrentWindows() throws {
        lastFullScanUptime = ProcessInfo.processInfo.systemUptime
        let frontmostProcessIdentifier = NSWorkspace.shared.frontmostApplication?
            .processIdentifier
        var refocusTarget: TargetIdentifier?
        var blockedNotice: String?

        for application in NSWorkspace.shared.runningApplications where
            application.activationPolicy == .regular
                && !application.isTerminated
                && application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        {
            guard
                let bundleIdentifier = application.bundleIdentifier,
                !AccessibilityWindowCatalog.isEssentialSystemApplication(
                    bundleIdentifier: bundleIdentifier
                )
            else {
                continue
            }

            let target = makeApplicationTarget(application)
            let windows = try windowCatalog.catalogueWindows(for: target)

            if application.processIdentifier == frontmostProcessIdentifier {
                if let focusedWindow = windows.first(where: \.isFocused) {
                    if case let .block(preferredTarget) = windowPolicy.handleActivation(
                        focusedWindow.observation
                    ) {
                        refocusTarget = preferredTarget
                        blockedNotice = "\(focusedWindow.target.title) is outside this focus session."
                    }
                } else if !isEntireApplicationAllowed(
                    bundleIdentifier: bundleIdentifier
                ) {
                    blockedNotice = "\(target.displayName) is outside this focus session."
                }
            }
            try enforce(windows: windows, applicationName: target.displayName)
        }

        if let blockedNotice {
            restoreAllowedFocus(preferredTarget: refocusTarget)
            publishBlockedNotice(blockedNotice)
        }
    }

    private func isEntireApplicationAllowed(bundleIdentifier: String) -> Bool {
        allowedTargets.contains { target in
            guard case let .application(application) = target else {
                return false
            }
            return application.bundleIdentifier == bundleIdentifier
        }
    }

    private func enforce(
        windows: [CataloguedAccessibilityWindow],
        applicationName: String
    ) throws {
        for window in windows where !windowPolicy.allows(window.observation) {
            try minimize(window.element, applicationName: applicationName)
        }
    }

    private func minimize(
        _ window: AXUIElement,
        applicationName: String
    ) throws {
        switch windowOperator.minimizedState(of: window) {
        case .minimized(true), .unavailable:
            return
        case .failed:
            throw ApplicationEnforcementError.windowControlUnavailable(applicationName)
        case .minimized(false):
            break
        }

        switch windowOperator.setMinimized(true, for: window) {
        case .success:
            restorationTracker.recordChangedWindow(window)
        case .unavailable:
            return
        case .failed:
            throw ApplicationEnforcementError.windowControlUnavailable(applicationName)
        }
    }

    private func activateInitialAllowedTarget() {
        restoreAllowedFocus(preferredTarget: allowedTargets.first?.id)
    }

    private func restoreAllowedFocus(preferredTarget: TargetIdentifier?) {
        let preferred = preferredTarget.flatMap { identifier in
            allowedTargets.first { $0.id == identifier }
        }
        let orderedTargets = (preferred.map { [$0] } ?? [])
            + allowedTargets.filter { $0.id != preferred?.id }

        for target in orderedTargets where activate(target) {
            return
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func activate(_ target: SessionTarget) -> Bool {
        switch target {
        case let .application(applicationTarget):
            guard let application = runningApplication(for: applicationTarget) else {
                return false
            }
            return application.activate(options: [.activateAllWindows])

        case let .window(windowTarget):
            guard
                let application = runningApplication(for: windowTarget.application),
                let element = windowCatalog.element(for: windowTarget.id)
            else {
                return false
            }
            _ = application.activate(options: [])
            return windowOperator.raise(element) == .success
        }
    }

    private func runningApplication(
        for target: ApplicationTarget
    ) -> NSRunningApplication? {
        let preferredApplication = target.processIdentifier.flatMap {
            NSRunningApplication(processIdentifier: $0)
        }
        if let preferredApplication,
           !preferredApplication.isTerminated,
           preferredApplication.bundleIdentifier == target.bundleIdentifier
        {
            return preferredApplication
        }

        return NSRunningApplication.runningApplications(
            withBundleIdentifier: target.bundleIdentifier
        ).first(where: { !$0.isTerminated })
    }

    private func makeApplicationTarget(
        _ application: NSRunningApplication
    ) -> ApplicationTarget {
        ApplicationTarget(
            displayName: application.localizedName ?? "Application",
            bundleIdentifier: application.bundleIdentifier ?? "",
            processIdentifier: application.processIdentifier,
            applicationURL: application.bundleURL
        )
    }

    private func publishBlockedNotice(_ message: String) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastNoticeUptime >= 2 else {
            return
        }

        lastNoticeUptime = now
        onBlockedApplication?(message)
    }
}
