import AppKit
import ApplicationServices
import StayPaneCore

enum ApplicationEnforcementError: LocalizedError {
    case accessibilityPermissionMissing
    case windowControlUnavailable(String)
    case allowedApplicationUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "Accessibility access is required before StayPane can start a session."
        case let .windowControlUnavailable(applicationName):
            "StayPane could not safely control \(applicationName)."
        case let .allowedApplicationUnavailable(applicationName):
            "\(applicationName) is no longer available."
        }
    }
}

@MainActor
final class ApplicationEnforcementController: NSObject, SessionEnforcing {
    var onBlockedApplication: ((String) -> Void)?
    var onEnforcementFailure: ((Error) -> Void)?

    private let permissionClient: AccessibilityPermissionClient
    private let notificationCenter: NotificationCenter
    private var allowedTarget: ApplicationTarget?
    private var changedWindows: [AXUIElement] = []
    private var isObserving = false
    private var lastNoticeAt = Date.distantPast

    init(
        permissionClient: AccessibilityPermissionClient,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.permissionClient = permissionClient
        self.notificationCenter = notificationCenter
        super.init()
    }

    func start(allowing target: ApplicationTarget) throws {
        guard permissionClient.isGranted, permissionClient.verifyWindowControl() else {
            throw ApplicationEnforcementError.accessibilityPermissionMissing
        }

        allowedTarget = target
        changedWindows.removeAll()
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
            throw error
        }
    }

    func stop() {
        endObservingActivations()

        for window in changedWindows {
            guard isWindowMinimized(window) == true else {
                continue
            }
            AXUIElementSetAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            )
        }

        changedWindows.removeAll()
        allowedTarget = nil
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
            onEnforcementFailure?(error)
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
            guard let isMinimized = isWindowMinimized(window) else {
                throw ApplicationEnforcementError.windowControlUnavailable(applicationName)
            }
            guard !isMinimized else {
                continue
            }

            let minimizeResult = AXUIElementSetAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                kCFBooleanTrue
            )

            guard minimizeResult == .success else {
                throw ApplicationEnforcementError.windowControlUnavailable(applicationName)
            }

            if !changedWindows.contains(where: { CFEqual($0, window) }) {
                changedWindows.append(window)
            }
        }
    }

    private func isWindowMinimized(_ window: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            &value
        )

        guard result == .success else {
            return nil
        }
        return value as? Bool
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
