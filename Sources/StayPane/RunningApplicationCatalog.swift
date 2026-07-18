import AppKit
import StayPaneCore

struct RunningApplicationItem: Identifiable {
    let target: ApplicationTarget
    let icon: NSImage

    var id: String {
        "\(target.bundleIdentifier)#\(target.processIdentifier)"
    }
}

@MainActor
final class RunningApplicationCatalog {
    func load() -> [RunningApplicationItem] {
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier

        return NSWorkspace.shared.runningApplications
            .filter { application in
                application.activationPolicy == .regular
                    && !application.isTerminated
                    && application.processIdentifier != ownProcessIdentifier
                    && application.bundleIdentifier != nil
                    && application.localizedName != nil
            }
            .compactMap { application in
                guard
                    let displayName = application.localizedName,
                    let bundleIdentifier = application.bundleIdentifier
                else {
                    return nil
                }

                let target = ApplicationTarget(
                    displayName: displayName,
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: application.processIdentifier
                )
                let icon = application.icon ?? NSImage(
                    systemSymbolName: "app",
                    accessibilityDescription: displayName
                ) ?? NSImage()

                return RunningApplicationItem(target: target, icon: icon)
            }
            .sorted {
                $0.target.displayName.localizedCaseInsensitiveCompare($1.target.displayName)
                    == .orderedAscending
            }
    }
}
