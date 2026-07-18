import AppKit
import ApplicationServices
import StayPaneCore
import StayPanePlatform

enum ApplicationEnforcementError: LocalizedError {
    case accessibilityPermissionMissing
    case windowControlUnavailable(String)
    case allowedApplicationsUnavailable([String])
    case windowRestorationPending(Int)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "Accessibility access is required before StayPane can start a session."
        case let .windowControlUnavailable(applicationName):
            "StayPane could not safely control \(applicationName)."
        case let .allowedApplicationsUnavailable(applicationNames):
            "These allowed applications are no longer installed: \(applicationNames.joined(separator: ", ")). Remove them or install them again before starting."
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

    private let permissionClient: AccessibilityPermissionClient
    private let notificationCenter: NotificationCenter
    private let windowOperator: any AccessibilityWindowOperating
    private let restorationTracker: WindowRestorationTracker
    private var allowedTargets: [ApplicationTarget] = []
    private var activationPolicy = ApplicationAllowlistPolicy(targets: [])
    private var isObserving = false
    private var lastNoticeAt = Date.distantPast

    init(
        permissionClient: AccessibilityPermissionClient,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        windowOperator: any AccessibilityWindowOperating = SystemAccessibilityWindowOperator()
    ) {
        self.permissionClient = permissionClient
        self.notificationCenter = notificationCenter
        self.windowOperator = windowOperator
        restorationTracker = WindowRestorationTracker(operatorClient: windowOperator)
        super.init()
    }

    func start(allowing targets: [ApplicationTarget]) throws {
        guard permissionClient.isGranted, permissionClient.verifyWindowControl() else {
            throw ApplicationEnforcementError.accessibilityPermissionMissing
        }
        let unavailableTargets = targets.filter { !isAvailable($0) }
        guard unavailableTargets.isEmpty else {
            throw ApplicationEnforcementError.allowedApplicationsUnavailable(
                unavailableTargets.map(\.displayName)
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
        activationPolicy = ApplicationAllowlistPolicy(targets: targets)
        beginObservingActivations()

        do {
            try minimizeCurrentlyDisallowedApplications()
            activateInitialAllowedApplicationIfRunning()
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

    func stop() {
        endObservingActivations()
        allowedTargets = []
        activationPolicy = ApplicationAllowlistPolicy(targets: [])

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
            let bundleIdentifier = application.bundleIdentifier
        else {
            return
        }

        let decision = activationPolicy.handleActivation(
            bundleIdentifier: bundleIdentifier
        )
        guard case let .block(refocusBundleIdentifier) = decision else {
            return
        }

        do {
            try minimizeWindows(of: application)
            restoreAllowedFocus(preferredBundleIdentifier: refocusBundleIdentifier)
            publishBlockedNotice(for: application.localizedName ?? "That app")
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

    private func minimizeCurrentlyDisallowedApplications() throws {
        guard !allowedTargets.isEmpty else {
            return
        }

        let allowedBundleIdentifiers = Set(allowedTargets.map(\.bundleIdentifier))

        for application in NSWorkspace.shared.runningApplications where
            application.activationPolicy == .regular
                && application.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && !allowedBundleIdentifiers.contains(application.bundleIdentifier ?? "")
                && !application.isHidden
        {
            try minimizeWindows(of: application)
        }
    }

    private func minimizeWindows(of application: NSRunningApplication) throws {
        let applicationName = application.localizedName ?? "a running application"
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &value
        )

        guard result == .success, let windows = value as? [AXUIElement] else {
            throw ApplicationEnforcementError.windowControlUnavailable(applicationName)
        }

        for window in windows {
            switch windowOperator.minimizedState(of: window) {
            case .minimized(true):
                continue

            case .unavailable:
                continue

            case .failed:
                throw ApplicationEnforcementError.windowControlUnavailable(applicationName)

            case .minimized(false):
                break
            }

            switch windowOperator.setMinimized(true, for: window) {
            case .success:
                restorationTracker.recordChangedWindow(window)
            case .unavailable:
                continue
            case .failed:
                throw ApplicationEnforcementError.windowControlUnavailable(applicationName)
            }
        }
    }

    private func isAvailable(_ target: ApplicationTarget) -> Bool {
        if !NSRunningApplication.runningApplications(
            withBundleIdentifier: target.bundleIdentifier
        ).filter({ !$0.isTerminated }).isEmpty {
            return true
        }

        if let applicationURL = target.applicationURL,
           FileManager.default.fileExists(atPath: applicationURL.path)
        {
            return true
        }

        return NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: target.bundleIdentifier
        ).map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false
    }

    private func activateInitialAllowedApplicationIfRunning() {
        guard let target = allowedTargets.first(where: {
            runningApplication(for: $0.bundleIdentifier, preferredProcessIdentifier: $0.processIdentifier)
                != nil
        }) else {
            return
        }

        _ = activationPolicy.handleActivation(
            bundleIdentifier: target.bundleIdentifier
        )
        _ = runningApplication(
            for: target.bundleIdentifier,
            preferredProcessIdentifier: target.processIdentifier
        )?.activate(options: [.activateAllWindows])
    }

    private func restoreAllowedFocus(preferredBundleIdentifier: String?) {
        let preferredTarget = preferredBundleIdentifier.flatMap { bundleIdentifier in
            allowedTargets.first { $0.bundleIdentifier == bundleIdentifier }
        }
        let orderedTargets = (preferredTarget.map { [$0] } ?? [])
            + allowedTargets.filter {
                $0.bundleIdentifier != preferredTarget?.bundleIdentifier
            }

        for target in orderedTargets {
            guard let application = runningApplication(
                for: target.bundleIdentifier,
                preferredProcessIdentifier: target.processIdentifier
            ) else {
                continue
            }
            _ = activationPolicy.handleActivation(
                bundleIdentifier: target.bundleIdentifier
            )
            if application.activate(options: [.activateAllWindows]) {
                return
            }
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func runningApplication(
        for bundleIdentifier: String,
        preferredProcessIdentifier: Int32?
    ) -> NSRunningApplication? {
        let preferredApplication = preferredProcessIdentifier.flatMap {
            NSRunningApplication(processIdentifier: $0)
        }
        if let preferredApplication,
           !preferredApplication.isTerminated,
           preferredApplication.bundleIdentifier == bundleIdentifier
        {
            return preferredApplication
        }

        return NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first(where: { !$0.isTerminated })
    }

    private func publishBlockedNotice(for applicationName: String) {
        let now = Date()
        guard now.timeIntervalSince(lastNoticeAt) >= 2 else {
            return
        }

        lastNoticeAt = now
        onBlockedApplication?("\(applicationName) is outside this focus session.")
    }
}
