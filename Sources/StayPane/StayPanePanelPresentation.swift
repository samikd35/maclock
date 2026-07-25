import CoreGraphics
import Foundation
import StayPaneCore

enum StayPaneSessionPresentationState: Equatable, Sendable {
    case onboarding
    case setup
    case review
    case countdown(startsAt: Date)
    case recovering(endsAt: Date)
    case active(endsAt: Date, targetCount: Int)
    case resetPending(targetCount: Int)
    case completed
    case endedEarly
    case interrupted

    static func resolve(
        state: SessionState,
        isReviewing: Bool,
        isOnboardingPresented: Bool
    ) -> StayPaneSessionPresentationState {
        if isOnboardingPresented {
            return .onboarding
        }
        if isReviewing {
            return .review
        }
        switch state {
        case .idle, .configuring, .ready:
            return .setup
        case let .starting(_, startsAt):
            return .countdown(startsAt: startsAt)
        case let .recovering(recovering):
            return .recovering(endsAt: recovering.activeSession.endsAt)
        case let .enforcing(active):
            return .active(
                endsAt: active.endsAt,
                targetCount: active.plan.targets.count
            )
        case let .resetPending(reset):
            return .resetPending(
                targetCount: reset.activeSession.plan.targets.count
            )
        case .completed:
            return .completed
        case .endedEarly:
            return .endedEarly
        case .interrupted:
            return .interrupted
        }
    }

    var panelPresentation: StayPanePanelPresentation {
        switch self {
        case .onboarding, .setup:
            .setup
        case .review:
            .review
        case .countdown, .recovering, .active, .resetPending:
            .active
        case .completed, .endedEarly:
            .completed
        case .interrupted:
            .interrupted
        }
    }

    var supportsPrimaryAction: Bool {
        switch self {
        case .setup, .review:
            true
        case .onboarding, .countdown, .recovering, .active, .resetPending,
             .completed, .endedEarly, .interrupted:
            false
        }
    }

    var supportsCancelNavigation: Bool {
        switch self {
        case .review, .countdown:
            true
        case .onboarding, .setup, .recovering, .active, .resetPending,
             .completed, .endedEarly, .interrupted:
            false
        }
    }
}

enum StayPanePanelPresentation: String, CaseIterable, Equatable, Sendable {
    case setup
    case review
    case active
    case completed
    case interrupted

    var preferredContentSize: CGSize {
        switch self {
        case .setup:
            CGSize(width: 720, height: 680)
        case .review:
            CGSize(width: 600, height: 520)
        case .active:
            CGSize(width: 480, height: 400)
        case .completed:
            CGSize(width: 460, height: 340)
        case .interrupted:
            CGSize(width: 560, height: 440)
        }
    }

    var minimumContentSize: CGSize {
        switch self {
        case .setup:
            CGSize(width: 600, height: 520)
        case .review:
            CGSize(width: 520, height: 440)
        case .active:
            CGSize(width: 420, height: 340)
        case .completed:
            CGSize(width: 420, height: 300)
        case .interrupted:
            CGSize(width: 500, height: 380)
        }
    }

    var title: String {
        switch self {
        case .setup:
            "New Session"
        case .review:
            "Review Session"
        case .active:
            "Focus Session"
        case .completed:
            "Session Complete"
        case .interrupted:
            "Session Interrupted"
        }
    }

    static func resolve(
        state: SessionState,
        isReviewing: Bool,
        isOnboardingPresented: Bool
    ) -> StayPanePanelPresentation {
        StayPaneSessionPresentationState.resolve(
            state: state,
            isReviewing: isReviewing,
            isOnboardingPresented: isOnboardingPresented
        ).panelPresentation
    }
}
