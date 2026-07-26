import AppKit
import Testing
@testable import StayPane

@MainActor
@Test func ordinaryTerminationUsesTheControlledQuitHandler() {
    let handler = FakeTerminationHandler(allowOrdinaryQuit: false)
    let delegate = StayPaneAppDelegate()
    delegate.model = handler

    let reply = delegate.applicationShouldTerminate(NSApplication.shared)

    #expect(reply == .terminateCancel)
    #expect(handler.quitRequestCount == 1)
    #expect(handler.systemTerminationCount == 0)
}

@MainActor
@Test func systemPowerOffDoesNotStartAnUnusableEarlyResetFlow() {
    let handler = FakeTerminationHandler(allowOrdinaryQuit: false)
    let delegate = StayPaneAppDelegate()
    delegate.model = handler
    delegate.workspaceWillPowerOff(
        Notification(name: NSWorkspace.willPowerOffNotification)
    )

    let reply = delegate.applicationShouldTerminate(NSApplication.shared)

    #expect(reply == .terminateNow)
    #expect(handler.quitRequestCount == 0)
    #expect(handler.systemTerminationCount == 1)
}

@MainActor
@Test func closingTheLastWindowKeepsTheDockAndMenuBarApplicationRunning() {
    let delegate = StayPaneAppDelegate()

    #expect(
        !delegate.applicationShouldTerminateAfterLastWindowClosed(
            NSApplication.shared
        )
    )
}

@MainActor
private final class FakeTerminationHandler: StayPaneTerminationHandling {
    let allowOrdinaryQuit: Bool
    var quitRequestCount = 0
    var systemTerminationCount = 0

    init(allowOrdinaryQuit: Bool) {
        self.allowOrdinaryQuit = allowOrdinaryQuit
    }

    func handleQuitRequest() -> Bool {
        quitRequestCount += 1
        return allowOrdinaryQuit
    }

    func prepareForSystemTermination() {
        systemTerminationCount += 1
    }
}
