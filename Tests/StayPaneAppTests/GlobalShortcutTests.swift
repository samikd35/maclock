import Testing
@testable import StayPane

@Test func theOnlyGlobalShortcutOpensTheStayPanePanel() {
    #expect(GlobalShortcutDefinition.registered.count == 1)
    #expect(GlobalShortcutDefinition.registered.first?.action == .openPanel)
    #expect(GlobalShortcutDefinition.registered.first?.displayName == "⌃⌥⌘S")
}
