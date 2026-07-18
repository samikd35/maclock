import Testing
@testable import StayPane

@Test func menuBarPresenceShowsFocusTimeOnlyDuringEnforcement() {
    #expect(SessionPresence.inactive.menuBarTitle == "StayPane")
    #expect(SessionPresence.active(remainingSeconds: 90).menuBarTitle == "1:30")
    #expect(
        SessionPresence.resetPending(
            focusRemainingSeconds: 90,
            resetRemainingSeconds: 7
        ).menuBarTitle == "Reset 0:07 · 1:30"
    )
}

@Test func onlyEnforcedSessionPresenceDisplaysTheFloatingTimer() {
    #expect(!SessionPresence.inactive.isEnforcing)
    #expect(SessionPresence.active(remainingSeconds: 90).isEnforcing)
    #expect(
        SessionPresence.resetPending(
            focusRemainingSeconds: 90,
            resetRemainingSeconds: 7
        ).isEnforcing
    )
}
