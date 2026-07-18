import Testing
@testable import StayPane

@Test func theOpenPanelShortcutHasOneNonDestructiveDefinition() {
    #expect(OpenPanelShortcutDefinition.registered.displayName == "⌃⌥⌘S")
}
