import AppKit
import StayPaneCore

enum ApplicationAvailability: Equatable {
    case running
    case installed
    case unavailable
}

struct ApplicationCatalogItem: Identifiable {
    let target: ApplicationTarget
    let icon: NSImage
    let availability: ApplicationAvailability

    var id: String {
        target.bundleIdentifier
    }

    var isRunning: Bool {
        availability == .running
    }

    var isAvailable: Bool {
        availability != .unavailable
    }
}

enum ApplicationCatalogError: LocalizedError {
    case invalidApplication

    var errorDescription: String? {
        "Choose an installed macOS application (.app)."
    }
}

@MainActor
protocol ApplicationAvailabilityResolving: AnyObject {
    func isAvailable(_ target: ApplicationTarget) -> Bool
}

@MainActor
final class ApplicationCatalog: ApplicationAvailabilityResolving {
    func load() -> [ApplicationCatalogItem] {
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier

        let items: [ApplicationCatalogItem] = NSWorkspace.shared.runningApplications
            .filter { application in
                application.activationPolicy == .regular
                    && !application.isTerminated
                    && application.processIdentifier != ownProcessIdentifier
                    && application.bundleIdentifier != nil
                    && application.localizedName != nil
            }
            .compactMap(makeRunningItem)
        var seenBundleIdentifiers: Set<String> = []
        return items
            .filter { seenBundleIdentifiers.insert($0.target.bundleIdentifier).inserted }
            .sorted(by: Self.sortByDisplayName)
    }

    func loadApplication(at applicationURL: URL) throws -> ApplicationCatalogItem {
        let standardizedURL = applicationURL.standardizedFileURL
        guard
            FileManager.default.fileExists(atPath: standardizedURL.path),
            standardizedURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
            let bundle = Bundle(url: standardizedURL),
            let bundleIdentifier = bundle.bundleIdentifier
        else {
            throw ApplicationCatalogError.invalidApplication
        }

        if let runningApplication = runningApplication(
            bundleIdentifier: bundleIdentifier
        ), let runningItem = makeRunningItem(runningApplication) {
            return runningItem
        }

        let displayName = Self.displayName(for: bundle, at: standardizedURL)
        return ApplicationCatalogItem(
            target: ApplicationTarget(
                displayName: displayName,
                bundleIdentifier: bundleIdentifier,
                applicationURL: standardizedURL
            ),
            icon: NSWorkspace.shared.icon(forFile: standardizedURL.path),
            availability: .installed
        )
    }

    func refresh(_ item: ApplicationCatalogItem) -> ApplicationCatalogItem {
        if let runningApplication = runningApplication(
            bundleIdentifier: item.target.bundleIdentifier
        ), let runningItem = makeRunningItem(runningApplication) {
            return runningItem
        }

        for applicationURL in candidateApplicationURLs(for: item.target) {
            if let installedItem = try? loadApplication(at: applicationURL) {
                return installedItem
            }
        }

        return ApplicationCatalogItem(
            target: ApplicationTarget(
                displayName: item.target.displayName,
                bundleIdentifier: item.target.bundleIdentifier,
                applicationURL: item.target.applicationURL
            ),
            icon: item.icon,
            availability: .unavailable
        )
    }

    func isAvailable(_ target: ApplicationTarget) -> Bool {
        if runningApplication(bundleIdentifier: target.bundleIdentifier) != nil {
            return true
        }

        return candidateApplicationURLs(for: target).contains { applicationURL in
            guard
                FileManager.default.fileExists(atPath: applicationURL.path),
                let bundle = Bundle(url: applicationURL)
            else {
                return false
            }
            return bundle.bundleIdentifier == target.bundleIdentifier
        }
    }

    private func makeRunningItem(
        _ application: NSRunningApplication
    ) -> ApplicationCatalogItem? {
        guard
            let displayName = application.localizedName,
            let bundleIdentifier = application.bundleIdentifier
        else {
            return nil
        }

        return ApplicationCatalogItem(
            target: ApplicationTarget(
                displayName: displayName,
                bundleIdentifier: bundleIdentifier,
                processIdentifier: application.processIdentifier,
                applicationURL: application.bundleURL?.standardizedFileURL
            ),
            icon: application.icon ?? NSImage(
                systemSymbolName: "app",
                accessibilityDescription: displayName
            ) ?? NSImage(),
            availability: .running
        )
    }

    private func runningApplication(
        bundleIdentifier: String
    ) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first(where: { !$0.isTerminated })
    }

    private func candidateApplicationURLs(
        for target: ApplicationTarget
    ) -> [URL] {
        var urls: [URL] = []
        if let applicationURL = target.applicationURL {
            urls.append(applicationURL.standardizedFileURL)
        }
        if let resolvedURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: target.bundleIdentifier
        )?.standardizedFileURL,
           !urls.contains(resolvedURL)
        {
            urls.append(resolvedURL)
        }
        return urls
    }

    private static func displayName(for bundle: Bundle, at url: URL) -> String {
        (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }

    private static func sortByDisplayName(
        _ left: ApplicationCatalogItem,
        _ right: ApplicationCatalogItem
    ) -> Bool {
        left.target.displayName.localizedCaseInsensitiveCompare(
            right.target.displayName
        ) == .orderedAscending
    }
}
