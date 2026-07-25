import StayPaneCore
import SwiftUI

struct StayPaneMenuBarView: View {
    @ObservedObject var model: StayPaneModel
    @ObservedObject var floatingTimerPreferences: FloatingTimerPreferenceModel
    let openStatusPanel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "rectangle.inset.filled.and.person.filled")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("StayPane")
                        .font(.headline)
                    Text(statusTitle)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
                Spacer()
            }

            Divider()

            statusContent

            if model.sessionPresence.isEnforcing {
                Toggle(
                    "Floating Timer",
                    isOn: Binding(
                        get: {
                            floatingTimerPreferences.value.isVisible
                        },
                        set: {
                            floatingTimerPreferences.setVisible($0)
                        }
                    )
                )
                .toggleStyle(.switch)
            }

            Button(openButtonTitle) {
                openStatusPanel()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .frame(width: 330)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("StayPane, \(statusTitle)")
    }

    @ViewBuilder
    private var statusContent: some View {
        switch sessionPresentationState {
        case .onboarding:
            compactMessage(
                title: "Setup required",
                detail: "Finish the local permission checklist before starting."
            )
        case .review:
            compactMessage(
                title: "Ready for review",
                detail: "\(model.formattedDuration) · \(targetCountDescription)"
            )
        case .setup:
            compactMessage(
                title: model.formattedDuration,
                detail: model.configuredTargets.isEmpty
                    ? "Choose what stays available"
                    : targetCountDescription
            )
        case let .countdown(startsAt):
            compactMessage(
                title: "Starting in \(model.countdownNumber)",
                detail: "Begins \(startsAt.formatted(date: .omitted, time: .standard))"
            )
        case let .recovering(endsAt):
            compactMessage(
                title: "Resuming Session",
                detail: "Ends \(formattedTime(endsAt))"
            )
        case let .active(endsAt, targetCount):
            VStack(alignment: .leading, spacing: 4) {
                Text(model.formattedRemainingTime)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("Ends \(formattedTime(endsAt)) · \(targetCount) Target\(targetCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case let .resetPending(targetCount):
            compactMessage(
                title: "Reset \(model.formattedEarlyResetRemainingTime)",
                detail: "\(model.formattedRemainingTime) focus time remains · \(targetCount) Targets locked"
            )
        case .completed:
            compactMessage(
                title: "Session complete",
                detail: "Open the summary for restoration status."
            )
        case .endedEarly:
            compactMessage(
                title: "Session ended early",
                detail: "Open the summary to start again."
            )
        case .interrupted:
            compactMessage(
                title: "Session interrupted",
                detail: "StayPane used Fail Open. Review the recovery details."
            )
        }
    }

    private func compactMessage(
        title: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var targetCountDescription: String {
        let count = model.configuredTargets.count
        return "\(count) Target\(count == 1 ? "" : "s") selected"
    }

    private var statusTitle: String {
        switch sessionPresentationState {
        case .onboarding:
            "Setup required"
        case .setup, .review:
            "Ready"
        case .countdown:
            "Starting"
        case .recovering:
            "Recovering"
        case .active:
            "Session locked"
        case .resetPending:
            "Early reset pending"
        case .completed:
            "Complete"
        case .endedEarly:
            "Ended early"
        case .interrupted:
            "Interrupted"
        }
    }

    private var statusColor: Color {
        switch sessionPresentationState {
        case .active:
            .green
        case .countdown, .recovering:
            .blue
        case .resetPending, .endedEarly, .interrupted:
            .orange
        case .onboarding, .setup, .review, .completed:
            .secondary
        }
    }

    private var openButtonTitle: String {
        switch sessionPresentationState {
        case .onboarding:
            "Open Setup"
        case .setup:
            "New Session"
        case .review:
            "Open Review"
        case .countdown, .recovering, .active, .resetPending:
            "Open Session"
        case .completed, .endedEarly, .interrupted:
            "Open Summary"
        }
    }

    private var sessionPresentationState: StayPaneSessionPresentationState {
        StayPaneSessionPresentationState.resolve(
            state: model.state,
            isReviewing: model.isReviewing,
            isOnboardingPresented: model.shouldPresentOnboarding
        )
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
