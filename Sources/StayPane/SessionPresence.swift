import Foundation

enum SessionPresence: Equatable {
    case inactive
    case active(remainingSeconds: Int)
    case resetPending(focusRemainingSeconds: Int, resetRemainingSeconds: Int)

    var isEnforcing: Bool {
        switch self {
        case .inactive:
            false
        case .active, .resetPending:
            true
        }
    }

    var menuBarTitle: String {
        switch self {
        case .inactive:
            "StayPane"
        case let .active(remainingSeconds):
            Self.format(seconds: remainingSeconds)
        case let .resetPending(focusRemainingSeconds, resetRemainingSeconds):
            "Reset \(Self.format(seconds: resetRemainingSeconds)) · "
                + Self.format(seconds: focusRemainingSeconds)
        }
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
