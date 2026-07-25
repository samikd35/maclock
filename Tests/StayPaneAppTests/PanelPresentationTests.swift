import CoreGraphics
import Testing
@testable import StayPane

@Test func statusPanelPresentationsProvideRoomyStateSpecificFrames() {
    #expect(StayPanePanelPresentation.setup.preferredContentSize == CGSize(width: 720, height: 680))
    #expect(StayPanePanelPresentation.setup.minimumContentSize == CGSize(width: 600, height: 520))
    #expect(StayPanePanelPresentation.review.preferredContentSize == CGSize(width: 600, height: 520))
    #expect(StayPanePanelPresentation.active.preferredContentSize == CGSize(width: 480, height: 400))
    #expect(StayPanePanelPresentation.recovery.preferredContentSize == CGSize(width: 560, height: 440))
    #expect(StayPanePanelPresentation.completed.preferredContentSize == CGSize(width: 460, height: 340))
    #expect(StayPanePanelPresentation.endedEarly.preferredContentSize == CGSize(width: 460, height: 340))
    #expect(StayPanePanelPresentation.interrupted.preferredContentSize == CGSize(width: 560, height: 440))
}

@Test func sessionPresentationStateOwnsCommandAndPanelAffordances() {
    #expect(StayPaneSessionPresentationState.onboarding.panelPresentation == .setup)
    #expect(StayPaneSessionPresentationState.setup.supportsPrimaryAction)
    #expect(StayPaneSessionPresentationState.review.supportsPrimaryAction)
    #expect(StayPaneSessionPresentationState.review.supportsCancelNavigation)
    #expect(
        StayPaneSessionPresentationState.countdown(startsAt: .distantFuture)
            .supportsCancelNavigation
    )
    #expect(
        !StayPaneSessionPresentationState.active(
            endsAt: .distantFuture,
            targetCount: 2
        ).supportsPrimaryAction
    )
    #expect(
        StayPaneSessionPresentationState.endedEarly.panelPresentation
            == .endedEarly
    )
    #expect(
        StayPaneSessionPresentationState.recovering(
            endsAt: .distantFuture
        ).panelPresentation == .recovery
    )
}
