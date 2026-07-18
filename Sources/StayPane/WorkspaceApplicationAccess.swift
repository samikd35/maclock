import AppKit

@MainActor
protocol WorkspaceApplicationAccessing: AnyObject {
    var runningApplications: [NSRunningApplication] { get }
    var frontmostApplication: NSRunningApplication? { get }
    func application(processIdentifier: Int32) -> NSRunningApplication?
    func runningApplications(bundleIdentifier: String) -> [NSRunningApplication]
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

    func runningApplications(
        bundleIdentifier: String
    ) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        )
    }
}
