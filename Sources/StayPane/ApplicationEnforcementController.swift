import AppKit
import ApplicationServices
import StayPaneCore
import StayPanePlatform

enum ApplicationEnforcementError: LocalizedError {
    case accessibilityPermissionMissing
    case windowControlUnavailable(String)
    case allowedApplicationUnavailable(String)
    case windowRestorationPending(Int)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "Accessibility access is required before StayPane can start a session."
        case let .windowControlUnavailable(applicationName):
            "StayPane could not safely control \(applicationName)."
        case let .allowedApplicationUnavailable(applicationName):
            "\(applicationName) is no longer available."
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
    private var allowedTarget: ApplicationTarget?
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

    func start(allowing target: ApplicationTarget) throws {
        guard permissionClient.isGranted, permissionClient.verifyWindowControl() else {
            throw ApplicationEnforcementError.accessibilityPermissionMissing
        }
        if restorationTracker.pendingCount > 0 {
            let outcome = restorationTracker.restorePendingWindows()
            guard outcome.pendingCount == 0 else {
                throw ApplicationEnforcementError.windowRestorationPending(
                    outcome.pendingCount
                )
            }
        }

        allowedTarget = target
        beginObservingActivations()

        do {
            try minimizeCurrentlyDisallowedApplications()
            guard activateAllowedApplication() else {
                throw ApplicationEnforcementError.allowedApplicationUnavailable(
                    target.displayName
                )
            }
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
        allowedTarget = nil

        let outcome = restorationTracker.restorePendingWindows()
        if outcome.pendingCount > 0 {
            onRestorationFailure?(outcome.pendingCount)
        }
    }

    func retryPendingRestorations() {
        guard allowedTarget == nil, restorationTracker.pendingCount > 0 else {
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
            let allowedTarget,
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            application.activationPolicy == .regular,
            application.bundleIdentifier != allowedTarget.bundleIdentifier
        else {
            return
        }

        do {
            try minimizeWindows(of: application)
            guard activateAllowedApplication() else {
                throw ApplicationEnforcementError.allowedApplicationUnavailable(
                    allowedTarget.displayName
                )
            }
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
        guard let allowedTarget else {
            return
        }

        for application in NSWorkspace.shared.runningApplications where
            application.activationPolicy == .regular
                && application.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && application.bundleIdentifier != allowedTarget.bundleIdentifier
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

    private func activateAllowedApplication() -> Bool {
        guard let allowedTarget else {
            return false
        }

        let application = NSRunningApplication(
            processIdentifier: allowedTarget.processIdentifier
        ) ?? NSRunningApplication.runningApplications(
            withBundleIdentifier: allowedTarget.bundleIdentifier
        ).first

        guard let application, !application.isTerminated else {
            return false
        }
        return application.activate(options: [.activateAllWindows])
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
