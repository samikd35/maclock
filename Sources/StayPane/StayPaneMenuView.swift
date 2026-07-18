import AppKit
import StayPaneCore
import SwiftUI

struct StayPaneMenuView: View {
    @ObservedObject var model: StayPaneModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let notice = model.notice {
                        NoticeBanner(message: notice)
                    }

                    content
                }
                .padding(16)
            }

            Divider()
            footer
        }
        .frame(width: 390, height: 540)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("StayPane")
                    .font(.headline)
                Text("Focus on the window that matters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        if model.isReviewing {
            reviewView
        } else {
            switch model.state {
            case .idle, .configuring, .ready:
                setupView
            case let .starting(plan, _):
                countdownView(plan: plan)
            case let .enforcing(activeSession):
                enforcingView(activeSession: activeSession)
            case let .resetPending(pendingReset):
                resetPendingView(pendingReset: pendingReset)
            case let .completed(completedSession):
                completedView(completedSession: completedSession)
            case let .endedEarly(endedSession):
                endedEarlyView(endedSession: endedSession)
            }
        }
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.accessibilityGranted || model.shouldExplainAccessibility {
                accessibilityCard
            } else {
                Label("Accessibility access verified", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Focus duration")
                    .font(.headline)

                HStack {
                    TextField("Seconds", value: $model.durationSeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.updateDuration() }
                        .onChange(of: model.durationSeconds) {
                            model.updateDuration()
                        }
                    Text("seconds")
                        .foregroundStyle(.secondary)
                }

                Text(model.formattedDuration)
                    .font(.title2.monospacedDigit().weight(.semibold))

                HStack {
                    ForEach([600, 1_500, 1_800, 3_600], id: \.self) { seconds in
                        Button(StayPaneModel.formatPreset(seconds: seconds)) {
                            model.durationSeconds = seconds
                            model.updateDuration()
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button("Reset") {
                        model.resetDurationToDefault()
                    }
                    .buttonStyle(.link)
                }

                if let message = model.durationValidationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Allowed range: 10 seconds to 24 hours. Your last duration is remembered.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Allowed application")
                        .font(.headline)
                    Spacer()
                    Button {
                        model.refreshApplications()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .labelStyle(.iconOnly)
                    .help("Refresh running applications")
                }

                Picker(
                    "Application",
                    selection: Binding(
                        get: { model.selectedApplicationID },
                        set: { model.chooseApplication(id: $0) }
                    )
                ) {
                    Text("Choose a running application…")
                        .tag(String?.none)
                    ForEach(model.applications) { application in
                        HStack {
                            Image(nsImage: application.icon)
                            Text(application.target.displayName)
                        }
                        .tag(Optional(application.id))
                    }
                }
                .labelsHidden()

                Text("All windows belonging to the selected app are allowed for this first version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Review session") {
                model.beginReview()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .disabled(!model.canReview)
        }
    }

    private var accessibilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Accessibility permission", systemImage: "hand.raised.fill")
                .font(.headline)
            Text("StayPane uses macOS Accessibility only to see, minimize, restore, and refocus app windows during a session. It never quits apps and does not need Screen Recording.")
                .font(.subheadline)
            Text("After granting access in System Settings, return here. StayPane verifies it automatically before enabling Start.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.accessibilityAuthorized && !model.accessibilityGranted {
                Text("Permission is enabled, but the harmless window-control check did not succeed. Open a normal app window, then choose Check Again.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
            HStack {
                Button("Request Access & Open Settings") {
                    model.requestAccessibilityAccess()
                }
                .buttonStyle(.borderedProminent)
                Button("Check Again") {
                    model.refreshAccessibilityStatus()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review your session")
                .font(.title2.weight(.semibold))
            Text("Once the countdown finishes, the allowed app and duration stay locked until the session ends.")
                .foregroundStyle(.secondary)

            reviewRow(
                title: "Allowed app",
                value: model.selectedApplication?.target.displayName ?? "Not selected",
                systemImage: "macwindow"
            )
            reviewRow(
                title: "Duration",
                value: model.formattedDuration,
                systemImage: "timer"
            )
            reviewRow(
                title: "Permission",
                value: model.accessibilityGranted ? "Verified" : "Missing",
                systemImage: model.accessibilityGranted ? "checkmark.seal" : "exclamationmark.triangle"
            )

            HStack {
                Button("Back") {
                    model.isReviewing = false
                }
                Spacer()
                Button("Start 3-second countdown") {
                    model.startCountdown()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func countdownView(plan: SessionPlan) -> some View {
        VStack(spacing: 18) {
            Text("Starting focus session")
                .font(.title2.weight(.semibold))
            Text("\(model.countdownNumber)")
                .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
            Text("Only \(plan.target.displayName) will remain available for \(model.formattedDuration).")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Cancel countdown") {
                model.cancelCountdown()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 35)
    }

    private func enforcingView(activeSession: ActiveSession) -> some View {
        VStack(spacing: 18) {
            Label("Focus session active", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(.green)

            Text(model.formattedRemainingTime)
                .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())

            VStack(spacing: 4) {
                Text("Allowed application")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(activeSession.plan.target.displayName)
                    .font(.title3.weight(.semibold))
            }

            Text("Other app windows are minimized. If you activate one, StayPane returns focus here without quitting anything.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("Session settings remain locked until the timer completes.")
                .font(.caption.weight(.medium))

            Button("End Session Early…", role: .destructive) {
                model.requestEarlyReset()
            }
            .buttonStyle(.bordered)

            honestBoundaryNote
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func resetPendingView(pendingReset: ResetPendingSession) -> some View {
        VStack(spacing: 16) {
            Label("Early reset requested", systemImage: "hourglass")
                .font(.headline)
                .foregroundStyle(.orange)

            if model.isEarlyResetConfirmationAvailable {
                Text("Final confirmation")
                    .font(.title2.weight(.semibold))
                Text("The 30-second waiting period is complete. Enforcement remains active until you make this final choice.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Keep focusing") {
                        model.declineEarlyResetConfirmation()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("End session now", role: .destructive) {
                        model.confirmEarlyReset()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("\(model.earlyResetCountdownNumber)")
                    .font(.system(size: 62, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("seconds until final confirmation")
                    .foregroundStyle(.secondary)
                Text("\(pendingReset.activeSession.plan.target.displayName) remains the only allowed application. The focus timer is still running.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button("Cancel early reset") {
                    model.cancelEarlyReset()
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Focus time remaining: \(model.formattedRemainingTime)")
                .font(.caption.monospacedDigit().weight(.medium))

            honestBoundaryNote
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func completedView(completedSession: CompletedSession) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("Session complete")
                .font(.title2.weight(.semibold))
            Text("You focused on \(completedSession.plan.target.displayName) for \(StayPaneModel.formatPreset(seconds: completedSession.plan.duration.seconds)).")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Only windows changed by StayPane were restored.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Start another session") {
                model.startAnotherSession()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 35)
    }

    private func endedEarlyView(endedSession: EndedEarlySession) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
            Text("Session ended early")
                .font(.title2.weight(.semibold))
            Text("Outcome: Ended Early")
                .font(.headline)
            Text("Focused for \(StayPaneModel.formatPreset(seconds: Int(endedSession.actualFocusDuration.rounded()))).")
                .foregroundStyle(.secondary)
            Text("StayPane restored only the windows it changed.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Start another session") {
                model.startAnotherSession()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 35)
    }

    private var honestBoundaryNote: some View {
        Text("Force Quit is a deliberate bypass outside StayPane’s honest self-control boundary.")
            .font(.caption2)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
    }

    private func reviewRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
            }
            Spacer()
        }
        .padding(10)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            Text("Local, source-only, and open source")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button(model.isActiveSession ? "Quit…" : "Quit") {
                if model.handleQuitRequest() {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.plain)
            .help(
                model.isActiveSession
                    ? "Quit uses the same 30-second early-reset flow"
                    : "Quit StayPane"
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

}

private struct NoticeBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "info.circle.fill")
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
