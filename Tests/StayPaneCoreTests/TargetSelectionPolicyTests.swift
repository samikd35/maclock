import Foundation
import Testing
@testable import StayPaneCore

@Test func selectingAnApplicationReplacesAndDisablesItsWindowTargets() {
    let application = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor",
        processIdentifier: 41
    )
    let window = WindowTarget(
        id: WindowIdentifier(rawValue: UUID(
            uuidString: "00000000-0000-0000-0000-000000000041"
        )!),
        title: "Draft",
        application: application
    )
    var policy = TargetSelectionPolicy()

    let selectedWindow = policy.select(.window(window))
    #expect(selectedWindow)
    #expect(policy.targets == [.window(window)])

    let selectedApplication = policy.select(.application(application))
    #expect(selectedApplication)
    #expect(policy.targets == [.application(application)])
    let redundantlySelectedWindow = policy.select(.window(window))
    #expect(!redundantlySelectedWindow)
    #expect(policy.targets == [.application(application)])

    policy.deselect(.application(bundleIdentifier: application.bundleIdentifier))
    let reselectedWindow = policy.select(.window(window))
    #expect(reselectedWindow)
    #expect(policy.targets == [.window(window)])
}
