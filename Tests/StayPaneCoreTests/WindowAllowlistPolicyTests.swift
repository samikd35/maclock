import Foundation
import Testing
@testable import StayPaneCore

@Test func preciseWindowTargetAllowsOnlyItAndItsTransientUI() {
    let selectedID = windowID("00000000-0000-0000-0000-000000000051")
    let siblingID = windowID("00000000-0000-0000-0000-000000000052")
    let transientID = windowID("00000000-0000-0000-0000-000000000053")
    let unrelatedDialogID = windowID("00000000-0000-0000-0000-000000000054")
    let application = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor"
    )
    let target = WindowTarget(
        id: selectedID,
        title: "Draft",
        application: application
    )
    let policy = WindowAllowlistPolicy(targets: [.window(target)])

    let examples: [(ObservedWindow, Bool)] = [
        (
            ObservedWindow(
                id: selectedID,
                bundleIdentifier: application.bundleIdentifier,
                relationship: .independent
            ),
            true
        ),
        (
            ObservedWindow(
                id: siblingID,
                bundleIdentifier: application.bundleIdentifier,
                relationship: .independent
            ),
            false
        ),
        (
            ObservedWindow(
                id: transientID,
                bundleIdentifier: application.bundleIdentifier,
                relationship: .transient(ancestorWindowIdentifiers: [selectedID])
            ),
            true
        ),
        (
            ObservedWindow(
                id: unrelatedDialogID,
                bundleIdentifier: application.bundleIdentifier,
                relationship: .transient(ancestorWindowIdentifiers: [siblingID])
            ),
            false
        ),
        (
            ObservedWindow(
                id: windowID("00000000-0000-0000-0000-000000000055"),
                bundleIdentifier: "com.apple.SecurityAgent",
                relationship: .essentialSystemInterface
            ),
            true
        )
    ]

    for (window, expected) in examples {
        #expect(policy.allows(window) == expected)
    }
}

@Test func reopenedWindowWithTheSameTitleIsASeparateBlockedWindow() {
    let selectedID = windowID("00000000-0000-0000-0000-000000000056")
    let reopenedID = windowID("00000000-0000-0000-0000-000000000057")
    let application = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor"
    )
    let selectedWindow = WindowTarget(
        id: selectedID,
        title: "Draft",
        application: application
    )
    let policy = WindowAllowlistPolicy(targets: [.window(selectedWindow)])

    #expect(
        !policy.allows(
            ObservedWindow(
                id: reopenedID,
                bundleIdentifier: application.bundleIdentifier,
                relationship: .independent
            )
        )
    )
}

@Test func blockedWindowReturnsFocusToTheMostRecentlyActivatedAllowedWindow() {
    let firstID = windowID("00000000-0000-0000-0000-000000000061")
    let secondID = windowID("00000000-0000-0000-0000-000000000062")
    let blockedID = windowID("00000000-0000-0000-0000-000000000063")
    let application = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor"
    )
    let targets: [SessionTarget] = [firstID, secondID].map { identifier in
        .window(
            WindowTarget(
                id: identifier,
                title: identifier == firstID ? "Draft" : "Notes",
                application: application
            )
        )
    }
    var policy = WindowAllowlistPolicy(targets: targets)

    let firstDecision = policy.handleActivation(
        ObservedWindow(
            id: firstID,
            bundleIdentifier: application.bundleIdentifier,
            relationship: .independent
        )
    )
    let secondDecision = policy.handleActivation(
        ObservedWindow(
            id: secondID,
            bundleIdentifier: application.bundleIdentifier,
            relationship: .independent
        )
    )
    let blockedDecision = policy.handleActivation(
        ObservedWindow(
            id: blockedID,
            bundleIdentifier: application.bundleIdentifier,
            relationship: .independent
        )
    )

    #expect(firstDecision == .allow)
    #expect(secondDecision == .allow)
    #expect(
        blockedDecision == .block(refocusTarget: .window(secondID))
    )
}

@Test func activatingTransientUIKeepsItsSelectedParentAsTheFocusTarget() {
    let selectedID = windowID("00000000-0000-0000-0000-000000000064")
    let sheetID = windowID("00000000-0000-0000-0000-000000000065")
    let blockedID = windowID("00000000-0000-0000-0000-000000000066")
    let application = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor"
    )
    let selectedWindow = WindowTarget(
        id: selectedID,
        title: "Draft",
        application: application
    )
    var policy = WindowAllowlistPolicy(targets: [.window(selectedWindow)])

    let transientDecision = policy.handleActivation(
        ObservedWindow(
            id: sheetID,
            bundleIdentifier: application.bundleIdentifier,
            relationship: .transient(ancestorWindowIdentifiers: [selectedID])
        )
    )
    let blockedDecision = policy.handleActivation(
        ObservedWindow(
            id: blockedID,
            bundleIdentifier: application.bundleIdentifier,
            relationship: .independent
        )
    )

    #expect(transientDecision == .allow)
    #expect(blockedDecision == .block(refocusTarget: .window(selectedID)))
}

private func windowID(_ value: String) -> WindowIdentifier {
    WindowIdentifier(rawValue: UUID(uuidString: value)!)
}
