import AppKit
import StayPaneCore

struct RunningApplicationItem: Identifiable {
    let target: ApplicationTarget
    let icon: NSImage

    var id: String {
        target.bundleIdentifier
    }

    var isRunning: Bool {
        target.processIdentifier != nil
    }

    var isAvailable: Bool {
        isRunning || target.applicationURL.map {
            FileManager.default.fileExists(atPath: $0.path)
        } == true
    }

    func asUnavailable() -> RunningApplicationItem {
        RunningApplicationItem(
            target: ApplicationTarget(
                displayName: target.displayName,
                bundleIdentifier: target.bundleIdentifier,
                applicationURL: target.applicationURL
            ),
            icon: icon
        )
    }
}

enum ApplicationCatalogError: LocalizedError {
    case invalidApplication

    var errorDescription: String? {
        "Choose an installed macOS application (.app)."
    }
}

@MainActor
final class RunningApplicationCatalog {
    func load() -> [RunningApplicationItem] {
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier

        let items: [RunningApplicationItem] = NSWorkspace.shared.runningApplications
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
                    processIdentifier: application.processIdentifier,
                    applicationURL: application.bundleURL?.standardizedFileURL
                )
                let icon = application.icon ?? NSImage(
                    systemSymbolName: "app",
                    accessibilityDescription: displayName
                ) ?? NSImage()

                return RunningApplicationItem(target: target, icon: icon)
            }
        var seenBundleIdentifiers: Set<String> = []
        return items
            .filter { seenBundleIdentifiers.insert($0.target.bundleIdentifier).inserted }
            .sorted {
                $0.target.displayName.localizedCaseInsensitiveCompare($1.target.displayName)
                    == .orderedAscending
            }
    }

    func loadApplication(at applicationURL: URL) throws -> RunningApplicationItem {
        let standardizedURL = applicationURL.standardizedFileURL
        guard
            standardizedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
            let bundle = Bundle(url: standardizedURL),
            let bundleIdentifier = bundle.bundleIdentifier
        else {
            throw ApplicationCatalogError.invalidApplication
        }

        let displayName = (bundle.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? standardizedURL.deletingPathExtension().lastPathComponent
        let runningApplication = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first(where: { !$0.isTerminated })
        let target = ApplicationTarget(
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: runningApplication?.processIdentifier,
            applicationURL: standardizedURL
        )

        return RunningApplicationItem(
            target: target,
            icon: NSWorkspace.shared.icon(forFile: standardizedURL.path)
        )
    }
}
