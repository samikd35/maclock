import Testing
@testable import StayPaneCore

@Test func defaultAndAcceptedBounds() {
    #expect(SessionDuration.default.seconds == 30 * 60)
    #expect(SessionDuration(seconds: 10)?.seconds == 10)
    #expect(SessionDuration(seconds: 24 * 60 * 60)?.seconds == 24 * 60 * 60)
}

@Test func rejectsValuesOutsideAcceptedBounds() {
    #expect(SessionDuration(seconds: 9) == nil)
    #expect(SessionDuration(seconds: 24 * 60 * 60 + 1) == nil)
}
