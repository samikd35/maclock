import Foundation

enum SetupHealthSeverity: Equatable, Sendable {
    case ready
    case attention
    case blocking
}

struct SetupHealthSummary: Equatable, Sendable {
    let severity: SetupHealthSeverity
    let title: String

    static func resolve(
        accessibilityReady: Bool,
        browserTargetsSelected: Bool,
        browserReady: Bool,
        recoveryReady: Bool
    ) -> SetupHealthSummary {
        if !accessibilityReady {
            return SetupHealthSummary(
                severity: .blocking,
                title: "Accessibility required"
            )
        }
        if browserTargetsSelected && !browserReady {
            return SetupHealthSummary(
                severity: .blocking,
                title: "Chrome setup required"
            )
        }
        if !recoveryReady {
            return SetupHealthSummary(
                severity: .attention,
                title: "Recovery needs attention"
            )
        }
        return SetupHealthSummary(
            severity: .ready,
            title: "Ready"
        )
    }
}
