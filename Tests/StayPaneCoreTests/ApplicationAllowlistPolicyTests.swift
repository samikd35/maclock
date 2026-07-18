import Testing
@testable import StayPaneCore

@Test func closedApplicationTargetAllowsItsFutureLaunchAndWindows() {
    let closedTarget = ApplicationTarget(
        displayName: "Research",
        bundleIdentifier: "com.example.research",
        processIdentifier: nil
    )
    var policy = ApplicationAllowlistPolicy(targets: [closedTarget])

    #expect(policy.allowsApplication(bundleIdentifier: "com.example.research"))
    #expect(
        policy.handleActivation(bundleIdentifier: "com.example.research") == .allow
    )
    #expect(policy.allowsApplication(bundleIdentifier: "com.example.research"))
}

@Test func blockedActivationReturnsToTheMostRecentlyActivatedAllowedApplication() {
    let editor = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor"
    )
    let reference = ApplicationTarget(
        displayName: "Reference",
        bundleIdentifier: "com.example.reference"
    )
    var policy = ApplicationAllowlistPolicy(targets: [editor, reference])

    #expect(
        policy.handleActivation(bundleIdentifier: "com.example.reference") == .allow
    )
    #expect(
        policy.handleActivation(bundleIdentifier: "com.example.editor") == .allow
    )
    #expect(
        policy.handleActivation(bundleIdentifier: "com.example.video")
            == .block(refocusBundleIdentifier: "com.example.editor")
    )
}
