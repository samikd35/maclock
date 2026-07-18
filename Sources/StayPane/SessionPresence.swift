import Foundation

enum SessionPresence: Equatable {
    case inactive
    case active(remainingSeconds: Int)
    case resetPending(focusRemainingSeconds: Int, resetRemainingSeconds: Int)
    case completed
    case endedEarly

    var isEnforcing: Bool {
        switch self {
        case .inactive, .completed, .endedEarly:
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
            formatSessionTime(seconds: remainingSeconds)
        case let .resetPending(focusRemainingSeconds, resetRemainingSeconds):
            "Reset \(formatSessionTime(seconds: resetRemainingSeconds)) · "
                + formatSessionTime(seconds: focusRemainingSeconds)
        case .completed:
            "Session Complete"
        case .endedEarly:
            "Ended Early"
        }
    }
}

func formatSessionTime(seconds: Int) -> String {
    let safeSeconds = max(0, seconds)
    let hours = safeSeconds / 3_600
    let minutes = (safeSeconds % 3_600) / 60
    let seconds = safeSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}
