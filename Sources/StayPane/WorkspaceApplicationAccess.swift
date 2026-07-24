import AppKit
import StayPaneCore

struct WorkspaceApplicationSnapshot: Equatable {
    let displayName: String
    let bundleIdentifier: String
    let processIdentifier: Int32
    let applicationURL: URL?

    init(
        displayName: String,
        bundleIdentifier: String,
        processIdentifier: Int32,
        applicationURL: URL? = nil
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.applicationURL = applicationURL
    }

    init?(_ application: NSRunningApplication) {
        guard
            application.activationPolicy == .regular,
            !application.isTerminated,
            let bundleIdentifier = application.bundleIdentifier
        else {
            return nil
        }
        self.init(
            displayName: application.localizedName ?? "Application",
            bundleIdentifier: bundleIdentifier,
            processIdentifier: application.processIdentifier,
            applicationURL: application.bundleURL
        )
    }

    var target: ApplicationTarget {
        ApplicationTarget(
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            applicationURL: applicationURL
        )
    }
}

@MainActor
protocol WorkspaceApplicationAccessing: AnyObject {
    var runningApplications: [NSRunningApplication] { get }
    var frontmostApplication: NSRunningApplication? { get }
    var runningApplicationSnapshots: [WorkspaceApplicationSnapshot] { get }
    var frontmostProcessIdentifier: Int32? { get }
    func application(processIdentifier: Int32) -> NSRunningApplication?
    func applicationSnapshot(
        processIdentifier: Int32
    ) -> WorkspaceApplicationSnapshot?
    func runningApplications(bundleIdentifier: String) -> [NSRunningApplication]
}

extension WorkspaceApplicationAccessing {
    var runningApplicationSnapshots: [WorkspaceApplicationSnapshot] {
        runningApplications.compactMap(WorkspaceApplicationSnapshot.init)
    }

    var frontmostProcessIdentifier: Int32? {
        frontmostApplication?.processIdentifier
    }

    func applicationSnapshot(
        processIdentifier: Int32
    ) -> WorkspaceApplicationSnapshot? {
        application(processIdentifier: processIdentifier)
            .flatMap(WorkspaceApplicationSnapshot.init)
    }
}

@MainActor
final class SystemWorkspaceApplicationAccess: WorkspaceApplicationAccessing {
    var runningApplications: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
    }

    var frontmostApplication: NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    func application(processIdentifier: Int32) -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: processIdentifier)
    }

    func applicationSnapshot(
        processIdentifier: Int32
    ) -> WorkspaceApplicationSnapshot? {
        guard
            let application = application(
                processIdentifier: processIdentifier
            ),
            !application.isTerminated,
            let bundleIdentifier = application.bundleIdentifier
        else {
            return nil
        }
        return WorkspaceApplicationSnapshot(
            displayName: application.localizedName ?? "Application",
            bundleIdentifier: bundleIdentifier,
            processIdentifier: application.processIdentifier,
            applicationURL: application.bundleURL
        )
    }

    func runningApplications(
        bundleIdentifier: String
    ) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        )
    }
}
