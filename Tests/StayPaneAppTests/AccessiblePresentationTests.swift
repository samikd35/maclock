import Foundation
import StayPaneCore
import Testing
@testable import StayPane

@Test func statusPanelWiresObservableSessionStatesToAccessibleFlows() {
    let now = Date(timeIntervalSince1970: 10_000)
    let duration = SessionDuration.default
    let target = SessionTarget.application(
        ApplicationTarget(
            displayName: "Editor",
            bundleIdentifier: "com.example.editor"
        )
    )
    let draft = SessionDraft(duration: duration, targets: [target])
    let plan = SessionPlan(
        duration: duration,
        targets: [target],
        preparedAt: now
    )
    let active = ActiveSession(
        plan: plan,
        startedAt: now,
        endsAt: now.addingTimeInterval(TimeInterval(duration.seconds)),
        continuousStartedAt: 1_000,
        continuousEndsAt: 1_000 + TimeInterval(duration.seconds)
    )
    let pendingReset = ResetPendingSession(
        activeSession: active,
        requestedAt: now,
        confirmationAvailableAt: now.addingTimeInterval(30),
        continuousConfirmationAvailableAt: 1_030
    )
    let states: [(SessionState, StatusPanelAccessibilityPresentation)] = [
        (.idle, .setup),
        (.configuring(draft), .setup),
        (.ready(draft), .setup),
        (.starting(plan: plan, startsAt: now.addingTimeInterval(3)), .countdown),
        (
            .recovering(
                RecoveringSession(activeSession: active, phase: .enforcing)
            ),
            .recovering
        ),
        (.enforcing(active), .active),
        (.resetPending(pendingReset), .resetWaiting),
        (
            .completed(CompletedSession(plan: plan, completedAt: active.endsAt)),
            .completed
        ),
        (
            .endedEarly(
                EndedEarlySession(
                    plan: plan,
                    startedAt: now,
                    endedAt: now.addingTimeInterval(60),
                    actualFocusDuration: 60
                )
            ),
            .endedEarly
        ),
        (
            .interrupted(
                InterruptedSession(
                    plan: plan,
                    startedAt: now,
                    interruptedAt: now.addingTimeInterval(60),
                    actualFocusDuration: 60,
                    reason: .enforcementUnavailable
                )
            ),
            .interrupted
        ),
    ]

    for (state, expected) in states {
        #expect(
            StatusPanelAccessibilityPresentation.resolve(
                shouldPresentOnboarding: false,
                isReviewing: false,
                sessionState: state,
                isResetConfirmationAvailable: false
            ) == expected
        )
    }
    #expect(
        StatusPanelAccessibilityPresentation.resolve(
            shouldPresentOnboarding: false,
            isReviewing: false,
            sessionState: .resetPending(pendingReset),
            isResetConfirmationAvailable: true
        ) == .resetConfirmation
    )
    #expect(
        StatusPanelAccessibilityPresentation.resolve(
            shouldPresentOnboarding: true,
            isReviewing: true,
            sessionState: .enforcing(active),
            isResetConfirmationAvailable: false
        ) == .onboarding
    )
    #expect(
        StatusPanelAccessibilityPresentation.resolve(
            shouldPresentOnboarding: false,
            isReviewing: true,
            sessionState: .enforcing(active),
            isResetConfirmationAvailable: false
        ) == .review
    )
}

@Test func statusPanelPresentsMeaningfulLabelsAcrossTheDailyFlow() {
    let presentations: [StatusPanelAccessibilityPresentation] = [
        .onboarding,
        .setup,
        .review,
        .countdown,
        .recovering,
        .active,
        .resetWaiting,
        .resetConfirmation,
        .completed,
        .endedEarly,
        .interrupted,
    ]

    for presentation in presentations {
        #expect(!presentation.title.isEmpty)
        #expect(!presentation.announcement.isEmpty)
    }
    #expect(
        StatusPanelAccessibilityPresentation.review.announcement
            == "Review the duration, Allowlist, integration status, completion feedback, and optional macOS Focus Reminder before starting."
    )
    #expect(
        StatusPanelAccessibilityPresentation.resetConfirmation.announcement
            == "The Early Reset waiting period is complete. Enforcement remains active until you keep focusing or confirm Ended Early."
    )
    #expect(
        StatusPanelAccessibilityPresentation.completed.title
            == "Session Complete"
    )
}

@Test func historyAndDiagnosticsExposePrivacySpecificAccessibleNames() {
    #expect(
        StayPaneAccessibilityText.targetHierarchyRegion.contains(
            "Application, Window, Browser Window, or Tab"
        )
    )
    #expect(
        StayPaneAccessibilityText.broadApplicationWarning.contains(
            "all current and future windows"
        )
    )
    #expect(
        StayPaneAccessibilityText.broadChromeApplicationWarning.contains(
            "every current and future Chrome window"
        )
    )
    #expect(
        StayPaneAccessibilityText.broadChromeWindowWarning.contains(
            "every current and future tab"
        )
    )
    #expect(
        StayPaneAccessibilityText.historyRegion
            == "Session History. Local records contain timing and result only, with no Target or browsing details."
    )
    #expect(
        StayPaneAccessibilityText.clearHistoryAction
            == "Clear all local Session History"
    )
    #expect(
        StayPaneAccessibilityText.clearHistoryWarning.contains("permanently")
    )
    #expect(
        StayPaneAccessibilityText.exportDiagnosticsAction
            == "Export redacted Diagnostics for local inspection"
    )
}

@Test func visualAccessibilityPolicyHonorsMotionAndContrastPreferences() {
    #expect(
        VisualAccessibilityPolicy(
            reduceMotion: false,
            increasedContrast: false
        ).usesAnimatedNumberTransitions
    )
    #expect(
        !VisualAccessibilityPolicy(
            reduceMotion: true,
            increasedContrast: false
        ).usesAnimatedNumberTransitions
    )
    #expect(
        VisualAccessibilityPolicy(
            reduceMotion: false,
            increasedContrast: false
        ).cardOpacity(standardOpacity: 0.08) == 0.08
    )
    #expect(
        VisualAccessibilityPolicy(
            reduceMotion: false,
            increasedContrast: true
        ).cardOpacity(standardOpacity: 0.08) == 0.16
    )
    #expect(
        VisualAccessibilityPolicy(
            reduceMotion: false,
            increasedContrast: true
        ).cardOpacity(standardOpacity: 0.2) == 0.28
    )
}
