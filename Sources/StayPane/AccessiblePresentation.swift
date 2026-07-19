import AppKit
import StayPaneCore

enum StatusPanelAccessibilityPresentation: Equatable {
    case onboarding
    case setup
    case review
    case countdown
    case recovering
    case active
    case resetWaiting
    case resetConfirmation
    case completed
    case endedEarly
    case interrupted

    static func resolve(
        shouldPresentOnboarding: Bool,
        isReviewing: Bool,
        sessionState: SessionState,
        isResetConfirmationAvailable: Bool
    ) -> Self {
        if shouldPresentOnboarding {
            return .onboarding
        }
        if isReviewing {
            return .review
        }
        switch sessionState {
        case .idle, .configuring, .ready:
            return .setup
        case .starting:
            return .countdown
        case .recovering:
            return .recovering
        case .enforcing:
            return .active
        case .resetPending:
            return isResetConfirmationAvailable
                ? .resetConfirmation
                : .resetWaiting
        case .completed:
            return .completed
        case .endedEarly:
            return .endedEarly
        case .interrupted:
            return .interrupted
        }
    }

    var title: String {
        descriptor.title
    }

    var announcement: String {
        descriptor.announcement
    }

    private var descriptor: (title: String, announcement: String) {
        switch self {
        case .onboarding:
            (
                "First-Run Onboarding",
                "First-Run Onboarding. Review the honest self-control boundary, local privacy, Accessibility verification, and optional Chrome setup."
            )
        case .setup:
            (
                "Session Setup",
                "Session Setup. Choose a duration and at least one Target for the Allowlist."
            )
        case .review:
            (
                "Review Session",
                "Review the duration, Allowlist, integration status, completion feedback, and optional macOS Focus Reminder before starting."
            )
        case .countdown:
            (
                "Starting Session",
                "The cancelable three-second Session start countdown has begun."
            )
        case .recovering:
            (
                "Recovering Session",
                "StayPane is verifying the saved Allowlist before resuming enforcement from its Fixed End Time."
            )
        case .active:
            (
                "Enforcement Active",
                "Enforcement is active. Session settings are immutable, and End Session Early remains available."
            )
        case .resetWaiting:
            (
                "Early Reset Waiting Period",
                "The 30-second Early Reset waiting period is running. The original Allowlist remains enforced."
            )
        case .resetConfirmation:
            (
                "Early Reset Final Confirmation",
                "The Early Reset waiting period is complete. Enforcement remains active until you keep focusing or confirm Ended Early."
            )
        case .completed:
            (
                "Session Complete",
                "Session Complete. Enforcement ended and eligible windows were restored."
            )
        case .endedEarly:
            (
                "Session Ended Early",
                "Session Ended Early. Enforcement ended after the controlled Early Reset flow."
            )
        case .interrupted:
            (
                "Session Interrupted",
                "Session Interrupted. StayPane used Fail Open because complete enforcement was no longer reliable."
            )
        }
    }
}

enum StayPaneAccessibilityText {
    static let targetHierarchyRegion =
        "Allowed Targets. Choose at the Application, Window, Browser Window, or Tab level; broader selections disable redundant child choices."
    static let broadApplicationWarning =
        "Broad Application Target warning: all current and future windows and content in each selected Application are allowed."
    static let broadChromeApplicationWarning =
        "Broad Chrome Application Target warning: every current and future Chrome window, tab, and website is allowed."
    static let broadChromeWindowWarning =
        "Broad Browser Window Target warning: every current and future tab and website in the selected Chrome window is allowed."
    static let historyRegion =
        "Session History. Local records contain timing and result only, with no Target or browsing details."
    static let clearHistoryAction = "Clear all local Session History"
    static let clearHistoryConfirmation = "Clear all Session History?"
    static let clearHistoryWarning =
        "This permanently removes all retained local Session History records."
    static let exportDiagnosticsAction =
        "Export redacted Diagnostics for local inspection"
}

struct VisualAccessibilityPolicy: Equatable {
    let reduceMotion: Bool
    let increasedContrast: Bool

    init(
        reduceMotion: Bool = false,
        increasedContrast: Bool = false
    ) {
        self.reduceMotion = reduceMotion
        self.increasedContrast = increasedContrast
    }

    var usesAnimatedNumberTransitions: Bool {
        !reduceMotion
    }

    func cardOpacity(
        standardOpacity: Double,
        increasedContrastMaximum: Double = 0.28
    ) -> Double {
        guard increasedContrast else {
            return standardOpacity
        }
        return min(standardOpacity * 2, increasedContrastMaximum)
    }
}

@MainActor
enum AccessibilityAnnouncer {
    static func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }
}
