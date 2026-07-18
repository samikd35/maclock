import Testing
@testable import StayPaneCore

@Test func activeSessionQuitWaitsForAControlledTerminalOutcome() {
    var coordinator = QuitCoordinator()

    let decision = coordinator.requestQuit(
        isSessionActive: true,
        pendingRestorationCount: 0
    )
    let whileActive = coordinator.consumeQuitWhenSafe(
        isSessionActive: true,
        pendingRestorationCount: 0
    )
    let afterOutcome = coordinator.consumeQuitWhenSafe(
        isSessionActive: false,
        pendingRestorationCount: 0
    )

    #expect(decision == .beginEarlyReset)
    #expect(whileActive == false)
    #expect(afterOutcome)
}

@Test func idleQuitWaitsForPendingRestorationThenTerminatesAutomatically() {
    var coordinator = QuitCoordinator()

    let decision = coordinator.requestQuit(
        isSessionActive: false,
        pendingRestorationCount: 1
    )
    let whilePending = coordinator.consumeQuitWhenSafe(
        isSessionActive: false,
        pendingRestorationCount: 1
    )
    let afterRestoration = coordinator.consumeQuitWhenSafe(
        isSessionActive: false,
        pendingRestorationCount: 0
    )

    #expect(decision == .waitForRestoration)
    #expect(whilePending == false)
    #expect(afterRestoration)
}

@Test func cancelingEarlyResetAlsoCancelsDeferredQuit() {
    var coordinator = QuitCoordinator()
    _ = coordinator.requestQuit(
        isSessionActive: true,
        pendingRestorationCount: 0
    )

    coordinator.cancelDeferredQuit()

    let shouldTerminate = coordinator.consumeQuitWhenSafe(
        isSessionActive: false,
        pendingRestorationCount: 0
    )
    #expect(shouldTerminate == false)
}

@Test func aPendingQuitRemainsDeferredWhileRecoveryIsProtected() {
    var coordinator = QuitCoordinator()

    #expect(
        coordinator.requestQuit(
            isSessionActive: true,
            pendingRestorationCount: 0
        ) == .beginEarlyReset
    )
    #expect(coordinator.hasPendingQuitRequest)
    #expect(
        coordinator.consumeQuitWhenSafe(
            isSessionActive: true,
            pendingRestorationCount: 0
        ) == false
    )
}
