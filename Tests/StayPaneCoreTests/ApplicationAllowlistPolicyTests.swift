import Foundation
import Testing
@testable import StayPaneCore

@Test func closedApplicationTargetAllowsItsFutureLaunchAndWindows() {
    let closedTarget = ApplicationTarget(
        displayName: "Research",
        bundleIdentifier: "com.example.research",
        processIdentifier: nil
    )
    var policy = WindowAllowlistPolicy(targets: [.application(closedTarget)])
    let futureWindow = ObservedWindow(
        id: WindowIdentifier(),
        bundleIdentifier: closedTarget.bundleIdentifier,
        relationship: .independent
    )

    #expect(policy.allows(futureWindow))
    let decision = policy.handleActivation(futureWindow)
    #expect(decision == .allow)
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
    var policy = WindowAllowlistPolicy(
        targets: [.application(editor), .application(reference)]
    )
    let referenceWindow = ObservedWindow(
        id: WindowIdentifier(),
        bundleIdentifier: reference.bundleIdentifier,
        relationship: .independent
    )
    let editorWindow = ObservedWindow(
        id: WindowIdentifier(),
        bundleIdentifier: editor.bundleIdentifier,
        relationship: .independent
    )
    let blockedWindow = ObservedWindow(
        id: WindowIdentifier(),
        bundleIdentifier: "com.example.video",
        relationship: .independent
    )

    let referenceDecision = policy.handleActivation(referenceWindow)
    let editorDecision = policy.handleActivation(editorWindow)
    let blockedDecision = policy.handleActivation(blockedWindow)

    #expect(referenceDecision == .allow)
    #expect(editorDecision == .allow)
    #expect(
        blockedDecision == .block(refocusTarget: .window(editorWindow.id))
    )
}
