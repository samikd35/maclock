import AppKit
import ApplicationServices

@MainActor
protocol AccessibilityPermissionChecking: AnyObject {
    var isGranted: Bool { get }
    func verifyWindowControl() -> Bool
}

@MainActor
final class AccessibilityPermissionClient: AccessibilityPermissionChecking {
    var isGranted: Bool {
        AXIsProcessTrusted()
    }

    func verifyWindowControl() -> Bool {
        guard isGranted else {
            return false
        }

        for application in NSWorkspace.shared.runningApplications where
            application.activationPolicy == .regular && !application.isTerminated
        {
            let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
            var windowsValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                applicationElement,
                kAXWindowsAttribute as CFString,
                &windowsValue
            ) == .success,
                let windows = windowsValue as? [AXUIElement]
            else {
                continue
            }

            for window in windows {
                var minimizedValue: CFTypeRef?
                var isSettable = DarwinBoolean(false)
                guard AXUIElementCopyAttributeValue(
                    window,
                    kAXMinimizedAttribute as CFString,
                    &minimizedValue
                ) == .success,
                    let isMinimized = minimizedValue as? Bool,
                    AXUIElementIsAttributeSettable(
                        window,
                        kAXMinimizedAttribute as CFString,
                        &isSettable
                    ) == .success,
                    isSettable.boolValue
                else {
                    continue
                }

                let unchangedValue = NSNumber(value: isMinimized)
                if AXUIElementSetAttributeValue(
                    window,
                    kAXMinimizedAttribute as CFString,
                    unchangedValue
                ) == .success {
                    return true
                }
            }
        }

        return false
    }

    @discardableResult
    func requestAccess() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
