import Testing
@testable import StayPane

@Test func recoveryNoticeKeepsUnconfirmedWindowMutationGuidanceVisible() {
    let presentation = StayPaneModel.noticePresentation(
        primaryMessage: "StayPane resumed the unfinished Session.",
        unconfirmedWindowMutationMessage:
            "Unconfirmed Window Mutation: restore the uncertain window manually."
    )

    #expect(
        presentation?.message
            == "StayPane resumed the unfinished Session. Unconfirmed Window Mutation: restore the uncertain window manually."
    )
    #expect(presentation?.isPersistent == true)
}

@Test func ordinaryRecoveryNoticeRemainsTransient() {
    let presentation = StayPaneModel.noticePresentation(
        primaryMessage: "StayPane resumed the unfinished Session.",
        unconfirmedWindowMutationMessage: nil
    )

    #expect(
        presentation?.message
            == "StayPane resumed the unfinished Session."
    )
    #expect(presentation?.isPersistent == false)
}
