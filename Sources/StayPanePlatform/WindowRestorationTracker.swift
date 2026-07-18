import ApplicationServices
import Foundation

public enum AccessibilityWindowState: Equatable, Sendable {
    case minimized(Bool)
    case unavailable
    case failed
}

public enum AccessibilityWindowWriteResult: Equatable, Sendable {
    case success
    case unavailable
    case failed
}

@MainActor
public protocol AccessibilityWindowOperating: AnyObject {
    func minimizedState(of window: AXUIElement) -> AccessibilityWindowState
    func setMinimized(_ minimized: Bool, for window: AXUIElement) -> AccessibilityWindowWriteResult
}

@MainActor
public final class SystemAccessibilityWindowOperator: AccessibilityWindowOperating {
    public init() {}

    public func minimizedState(of window: AXUIElement) -> AccessibilityWindowState {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            &value
        )

        if result == .invalidUIElement {
            return .unavailable
        }
        guard result == .success, let minimized = value as? Bool else {
            return .failed
        }
        return .minimized(minimized)
    }

    public func setMinimized(
        _ minimized: Bool,
        for window: AXUIElement
    ) -> AccessibilityWindowWriteResult {
        let value = NSNumber(value: minimized)
        let result = AXUIElementSetAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            value
        )

        if result == .invalidUIElement {
            return .unavailable
        }
        return result == .success ? .success : .failed
    }
}

public struct WindowRestorationOutcome: Equatable, Sendable {
    public let restoredCount: Int
    public let resolvedUnavailableCount: Int
    public let pendingCount: Int

    public init(
        restoredCount: Int,
        resolvedUnavailableCount: Int,
        pendingCount: Int
    ) {
        self.restoredCount = restoredCount
        self.resolvedUnavailableCount = resolvedUnavailableCount
        self.pendingCount = pendingCount
    }
}

@MainActor
public final class WindowRestorationTracker {
    public var pendingCount: Int {
        windows.count
    }

    private let operatorClient: any AccessibilityWindowOperating
    private var windows: [AXUIElement] = []

    public init(operatorClient: any AccessibilityWindowOperating) {
        self.operatorClient = operatorClient
    }

    public func recordChangedWindow(_ window: AXUIElement) {
        guard !windows.contains(where: { CFEqual($0, window) }) else {
            return
        }
        windows.append(window)
    }

    @discardableResult
    public func restorePendingWindows() -> WindowRestorationOutcome {
        var restoredCount = 0
        var resolvedUnavailableCount = 0
        var stillPending: [AXUIElement] = []

        for window in windows {
            switch operatorClient.minimizedState(of: window) {
            case .minimized(false):
                continue

            case .unavailable:
                resolvedUnavailableCount += 1

            case .failed:
                stillPending.append(window)

            case .minimized(true):
                switch operatorClient.setMinimized(false, for: window) {
                case .success:
                    restoredCount += 1
                case .unavailable:
                    resolvedUnavailableCount += 1
                case .failed:
                    stillPending.append(window)
                }
            }
        }

        windows = stillPending
        return WindowRestorationOutcome(
            restoredCount: restoredCount,
            resolvedUnavailableCount: resolvedUnavailableCount,
            pendingCount: stillPending.count
        )
    }
}
