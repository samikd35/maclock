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
                    Text(menuBarPresentation.statusTitle)
                        .font(.caption)
                        .foregroundStyle(menuBarPresentation.statusColor)
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

            Button(menuBarPresentation.openButtonTitle) {
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
        .accessibilityLabel(
            "StayPane, \(menuBarPresentation.statusTitle)"
        )
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

    private var menuBarPresentation: MenuBarPresentation {
        switch sessionPresentationState {
        case .onboarding:
            MenuBarPresentation(
                statusTitle: "Setup required",
                statusColor: .secondary,
                openButtonTitle: "Open Setup"
            )
        case .setup, .review:
            MenuBarPresentation(
                statusTitle: "Ready",
                statusColor: .secondary,
                openButtonTitle: sessionPresentationState == .review
                    ? "Open Review"
                    : "New Session"
            )
        case .countdown:
            MenuBarPresentation(
                statusTitle: "Starting",
                statusColor: .blue,
                openButtonTitle: "Open Session"
            )
        case .recovering:
            MenuBarPresentation(
                statusTitle: "Recovering",
                statusColor: .blue,
                openButtonTitle: "Open Session"
            )
        case .active:
            MenuBarPresentation(
                statusTitle: "Session locked",
                statusColor: .green,
                openButtonTitle: "Open Session"
            )
        case .resetPending:
            MenuBarPresentation(
                statusTitle: "Early reset pending",
                statusColor: .orange,
                openButtonTitle: "Open Session"
            )
        case .completed:
            MenuBarPresentation(
                statusTitle: "Complete",
                statusColor: .secondary,
                openButtonTitle: "Open Summary"
            )
        case .endedEarly:
            MenuBarPresentation(
                statusTitle: "Ended early",
                statusColor: .orange,
                openButtonTitle: "Open Summary"
            )
        case .interrupted:
            MenuBarPresentation(
                statusTitle: "Interrupted",
                statusColor: .orange,
                openButtonTitle: "Open Summary"
            )
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

    private struct MenuBarPresentation {
        let statusTitle: String
        let statusColor: Color
        let openButtonTitle: String
    }
}
