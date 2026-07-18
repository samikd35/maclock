import ApplicationServices
import Testing
@testable import StayPanePlatform

@MainActor
@Test func failedRestorationsRemainTrackedUntilARetrySucceeds() {
    let successfulWindow = AXUIElementCreateApplication(101)
    let retryWindow = AXUIElementCreateApplication(202)
    let operatorClient = FakeWindowOperator(retryWindow: retryWindow)
    let tracker = WindowRestorationTracker(operatorClient: operatorClient)
    tracker.recordChangedWindow(successfulWindow)
    tracker.recordChangedWindow(retryWindow)

    let firstOutcome = tracker.restorePendingWindows()

    #expect(firstOutcome.restoredCount == 1)
    #expect(firstOutcome.pendingCount == 1)
    #expect(tracker.pendingCount == 1)

    operatorClient.shouldFailRetryWindow = false
    let retryOutcome = tracker.restorePendingWindows()

    #expect(retryOutcome.restoredCount == 1)
    #expect(retryOutcome.pendingCount == 0)
    #expect(tracker.pendingCount == 0)
}

@MainActor
@Test func closedWindowsAreResolvedWithoutAWriteAttempt() {
    let closedWindow = AXUIElementCreateApplication(303)
    let operatorClient = FakeWindowOperator(
        retryWindow: closedWindow,
        retryState: .unavailable
    )
    let tracker = WindowRestorationTracker(operatorClient: operatorClient)
    tracker.recordChangedWindow(closedWindow)

    let outcome = tracker.restorePendingWindows()

    #expect(outcome.resolvedUnavailableCount == 1)
    #expect(outcome.pendingCount == 0)
    #expect(operatorClient.writeCount == 0)
}

@MainActor
private final class FakeWindowOperator: AccessibilityWindowOperating {
    let retryWindow: AXUIElement
    var retryState: AccessibilityWindowState
    var shouldFailRetryWindow = true
    var writeCount = 0

    init(
        retryWindow: AXUIElement,
        retryState: AccessibilityWindowState = .minimized(true)
    ) {
        self.retryWindow = retryWindow
        self.retryState = retryState
    }

    func minimizedState(of window: AXUIElement) -> AccessibilityWindowState {
        CFEqual(window, retryWindow) ? retryState : .minimized(true)
    }

    func setMinimized(
        _ minimized: Bool,
        for window: AXUIElement
    ) -> AccessibilityWindowWriteResult {
        writeCount += 1
        if CFEqual(window, retryWindow), shouldFailRetryWindow {
            return .failed
        }
        return .success
    }

    func raise(_ window: AXUIElement) -> AccessibilityWindowWriteResult {
        .success
    }
}
