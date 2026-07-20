import AppKit
import ApplicationServices
import Foundation
import StayPanePlatform
import Testing
@testable import StayPane

@MainActor
@Test(
    .enabled(
        if: ProcessInfo.processInfo.environment["STAYPANE_RUN_AX_INTEGRATION_TESTS"]
            == "1",
        "Set STAYPANE_RUN_AX_INTEGRATION_TESTS=1 to exercise the real macOS adapter."
    )
)
func systemAccessibilityAdapterControlsAFixtureWindowWhenOptedIn() throws {
    guard AXIsProcessTrusted() else {
        Issue.record(
            "Grant Accessibility access to the test host before running the opt-in AX integration test."
        )
        return
    }

    let title = "StayPane AX Fixture \(UUID().uuidString)"
    let fixtureWindow = NSWindow(
        contentRect: CGRect(x: 120, y: 120, width: 420, height: 240),
        styleMask: [.titled, .closable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    fixtureWindow.title = title
    fixtureWindow.setAccessibilityIdentifier(nil)
    fixtureWindow.makeKeyAndOrderFront(nil)
    defer {
        fixtureWindow.orderOut(nil)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))

    let provider = SystemAccessibilityWindowProvider()
    let descriptors = try provider.windows(
        processIdentifier: ProcessInfo.processInfo.processIdentifier
    )
    let fixture = try #require(descriptors.first { $0.title == title })
    let operatorClient = SystemAccessibilityWindowOperator()

    #expect(fixture.frame != nil)
    #expect(fixture.isFocused)
    #expect(fixture.accessibilityIdentifier == nil)
    #expect(
        fixture.coreGraphicsWindowNumber
            == UInt32(fixtureWindow.windowNumber)
    )
    #expect(operatorClient.minimizedState(of: fixture.element) == .minimized(false))
    #expect(operatorClient.setMinimized(true, for: fixture.element) == .success)
    #expect(operatorClient.minimizedState(of: fixture.element) == .minimized(true))
    #expect(operatorClient.setMinimized(false, for: fixture.element) == .success)
    #expect(operatorClient.raise(fixture.element) == .success)
}
