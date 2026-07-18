import ApplicationServices
import Foundation
import StayPaneCore
import StayPanePlatform
import Testing
@testable import StayPane

@MainActor
@Test func targetDisappearanceAtCountdownBoundaryPreservesDraftAndNamesTarget() throws {
    let clock = EnforcementTestClock(
        now: Date(timeIntervalSince1970: 20_000)
    )
    let resolver = FakeApplicationAvailabilityResolver(available: false)
    let controller = ApplicationEnforcementController(
        permissionClient: AccessibilityPermissionClient(),
        availabilityResolver: resolver,
        notificationCenter: NotificationCenter(),
        windowOperator: UnusedWindowOperator()
    )
    let engine = SessionEngine(clock: clock, enforcement: controller)
    let target = ApplicationTarget(
        displayName: "Research",
        bundleIdentifier: "com.example.research",
        applicationURL: URL(fileURLWithPath: "/Applications/Research.app")
    )

    engine.beginConfiguration()
    engine.select(target: target)
    try engine.beginStartCountdown(seconds: 3)
    clock.advance(by: 3)

    let expectedError = ApplicationEnforcementError.allowedApplicationsUnavailable(
        ["Research"]
    )
    #expect(throws: expectedError) {
        try engine.advance()
    }

    guard case let .ready(draft) = engine.state else {
        Issue.record("A disappeared target should abort enforcement")
        return
    }
    #expect(draft.targets == [target])
    #expect(expectedError.localizedDescription.contains("Research"))
    #expect(expectedError.localizedDescription.contains("no longer installed"))
}

@MainActor
private final class EnforcementTestClock: SessionClock {
    var now: Date
    var continuousNow: TimeInterval = 0

    init(now: Date) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        continuousNow += seconds
    }
}

@MainActor
private final class FakeApplicationAvailabilityResolver: ApplicationAvailabilityResolving {
    let available: Bool

    init(available: Bool) {
        self.available = available
    }

    func isAvailable(_ target: ApplicationTarget) -> Bool {
        available
    }
}

@MainActor
private final class UnusedWindowOperator: AccessibilityWindowOperating {
    func minimizedState(of window: AXUIElement) -> AccessibilityWindowState {
        .failed
    }

    func setMinimized(
        _ minimized: Bool,
        for window: AXUIElement
    ) -> AccessibilityWindowWriteResult {
        .failed
    }
}
