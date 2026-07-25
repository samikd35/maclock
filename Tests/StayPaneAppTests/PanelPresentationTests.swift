import CoreGraphics
import Testing
@testable import StayPane

@Test func statusPanelPresentationsProvideRoomyStateSpecificFrames() {
    #expect(StayPanePanelPresentation.setup.preferredContentSize == CGSize(width: 720, height: 680))
    #expect(StayPanePanelPresentation.setup.minimumContentSize == CGSize(width: 600, height: 520))
    #expect(StayPanePanelPresentation.review.preferredContentSize == CGSize(width: 600, height: 520))
    #expect(StayPanePanelPresentation.active.preferredContentSize == CGSize(width: 480, height: 400))
    #expect(StayPanePanelPresentation.completed.preferredContentSize == CGSize(width: 460, height: 340))
    #expect(StayPanePanelPresentation.interrupted.preferredContentSize == CGSize(width: 560, height: 440))
}
