import AppKit
import Testing
@testable import StayPane

@MainActor
@Test func statusPanelUsesANormalApplicationWindow() {
    let window = StayPanePanelController.makeWindow(
        for: .setup
    )

    #expect(type(of: window) == NSWindow.self)
    #expect(window.level == .normal)
    #expect(!window.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(window.styleMask.contains(.miniaturizable))
    #expect(window.styleMask.contains(.resizable))
}
