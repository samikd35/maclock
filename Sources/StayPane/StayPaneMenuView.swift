import AppKit
import StayPaneCore
import SwiftUI

struct StayPaneMenuView: View {
    @ObservedObject var model: StayPaneModel
    @ObservedObject var floatingTimerPreferences: FloatingTimerPreferenceModel

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
                    Text("Allowed targets")
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

                if model.applications.isEmpty {
                    Text("No running applications found. Add an installed application instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(model.applications, id: \.id) { application in
                            applicationPickerRow(application)
                        }
                    }
                }

                Button {
                    model.addInstalledApplication()
                } label: {
                    Label("Add Installed Application…", systemImage: "plus.app")
                }
                .buttonStyle(.bordered)

                if !model.selectedApplicationIDs.isEmpty {
                    broadApplicationWarning
                }
                if !model.selectedWindowIDs.isEmpty {
                    preciseWindowNote
                }
            }

            floatingTimerSetupCard

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
            Text("Once the countdown finishes, the selected targets and duration stay locked until the session ends.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Allowed targets")
                    .font(.headline)
                ForEach(model.configuredTargets, id: \.id) { target in
                    let presentation = targetPresentation(target)
                    reviewRow(
                        title: presentation.reviewTitle,
                        value: presentation.reviewValue,
                        systemImage: presentation.systemImage
                    )
                }
            }
            if model.configuredTargets.contains(where: {
                targetPresentation($0).isBroadApplication
            }) {
                broadApplicationWarning
            }
            if model.configuredTargets.contains(where: {
                !targetPresentation($0).isBroadApplication
            }) {
                preciseWindowNote
            }
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
            reviewRow(
                title: "Floating Timer",
                value: floatingTimerPreferenceSummary,
                systemImage: "timer"
            )

            VStack(alignment: .leading, spacing: 8) {
                Label("Optional macOS Focus reminder", systemImage: "moon.fill")
                    .font(.headline)
                Text("StayPane cannot reliably toggle macOS Focus and does not automate Control Center. Enable Focus yourself if you also want notifications silenced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Focus Settings") {
                    model.openFocusSettings()
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

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
            Text("Only \(targetNames(plan.targets)) will remain available for \(model.formattedDuration).")
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
            Label("Enforcement active", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(.green)

            Text(model.formattedRemainingTime)
                .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())

            VStack(spacing: 6) {
                Text("Allowed targets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(activeSession.plan.targets, id: \.id) { target in
                    Text(targetLabel(target))
                        .font(.title3.weight(.semibold))
                }
            }

            Text("Other application windows are minimized. Sheets and dialogs attached to an allowed window remain usable; unrelated windows stay blocked.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("Session settings remain locked until the timer completes.")
                .font(.caption.weight(.medium))

            floatingTimerControls

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
                Text("The original allowlist—\(targetNames(pendingReset.activeSession.plan.targets))—remains enforced. The focus timer is still running.")
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

            floatingTimerControls

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
            Text("You focused with \(targetNames(completedSession.plan.targets)) for \(StayPaneModel.formatPreset(seconds: completedSession.plan.duration.seconds)).")
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

    private var floatingTimerControls: some View {
        VStack(spacing: 6) {
            HStack {
                Button(
                    floatingTimerPreferences.value.isVisible
                        ? "Hide Floating Timer"
                        : "Show Floating Timer"
                ) {
                    floatingTimerPreferences.setVisible(
                        !floatingTimerPreferences.value.isVisible
                    )
                }
                .buttonStyle(.bordered)

                if floatingTimerPreferences.value.isVisible {
                    Button(
                        floatingTimerPreferences.value.isCollapsed
                            ? "Expand"
                            : "Collapse"
                    ) {
                        floatingTimerPreferences.toggleCollapsed()
                    }
                    .buttonStyle(.bordered)
                }
            }
            Text("The floating timer is native, movable, and optional. The menu-bar timer remains visible when it is hidden.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var floatingTimerSetupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Floating Timer", systemImage: "timer")
                .font(.headline)
            Toggle(
                "Show during the Session",
                isOn: Binding(
                    get: { floatingTimerPreferences.value.isVisible },
                    set: { floatingTimerPreferences.setVisible($0) }
                )
            )
            .toggleStyle(.switch)
            Toggle(
                "Start collapsed",
                isOn: Binding(
                    get: { floatingTimerPreferences.value.isCollapsed },
                    set: { floatingTimerPreferences.setCollapsed($0) }
                )
            )
            .toggleStyle(.switch)
            .disabled(!floatingTimerPreferences.value.isVisible)
            Text("A native movable countdown above your work. It is never injected into webpages.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var floatingTimerPreferenceSummary: String {
        guard floatingTimerPreferences.value.isVisible else {
            return "Hidden; menu-bar countdown remains"
        }
        return floatingTimerPreferences.value.isCollapsed
            ? "Visible, collapsed"
            : "Visible, expanded"
    }

    private var broadApplicationWarning: some View {
        Label(
            "Application targets are broad. Every existing and future window—and all content inside each selected application—is allowed during the session.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(.orange)
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(
            "Broad application access warning: all current and future windows and content in each selected application are allowed."
        )
    }

    private var preciseWindowNote: some View {
        Label(
            "Window targets are precise. Only each chosen window and its attached sheets or modal dialogs are allowed; sibling and newly opened independent windows stay blocked.",
            systemImage: "macwindow.on.rectangle"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(.blue)
        .padding(10)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func applicationPickerRow(
        _ application: ApplicationCatalogItem
    ) -> some View {
        if application.isRunning {
            DisclosureGroup(
                isExpanded: Binding(
                    get: {
                        model.expandedApplicationIDs.contains(application.id)
                    },
                    set: {
                        model.setApplicationExpanded(
                            id: application.id,
                            isExpanded: $0
                        )
                    }
                )
            ) {
                let windows = model.windows(for: application.id)
                if windows.isEmpty {
                    Text("No current windows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(windows, id: \.id) { window in
                            Toggle(
                                isOn: Binding(
                                    get: {
                                        model.selectedWindowIDs.contains(window.id)
                                    },
                                    set: {
                                        model.setWindow(
                                            id: window.id,
                                            isSelected: $0
                                        )
                                    }
                                )
                            ) {
                                Label(
                                    window.title,
                                    systemImage: "macwindow"
                                )
                                .font(.subheadline)
                            }
                            .toggleStyle(.checkbox)
                            .disabled(
                                model.selectedApplicationIDs.contains(application.id)
                            )
                            .padding(.leading, 24)
                            .onHover {
                                model.highlightWindow(
                                    id: window.id,
                                    isHighlighted: $0
                                )
                            }
                        }
                    }
                }
            } label: {
                applicationToggle(application)
            }
        } else {
            applicationToggle(application)
        }
    }

    private func applicationToggle(
        _ application: ApplicationCatalogItem
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: {
                    model.selectedApplicationIDs.contains(application.id)
                },
                set: {
                    model.setApplication(id: application.id, isSelected: $0)
                }
            )
        ) {
            HStack(spacing: 8) {
                Image(nsImage: application.icon)
                    .resizable()
                    .frame(width: 22, height: 22)
                Text(application.target.displayName)
                Spacer()
                Text(applicationStatus(application))
                    .font(.caption2)
                    .foregroundStyle(
                        application.isAvailable ? Color.secondary : Color.red
                    )
            }
        }
        .toggleStyle(.checkbox)
        .disabled(
            !application.isAvailable
                && !model.selectedApplicationIDs.contains(application.id)
        )
    }

    private func applicationStatus(_ application: ApplicationCatalogItem) -> String {
        if application.isRunning {
            return "Running"
        }
        return application.isAvailable ? "Installed" : "Unavailable"
    }

    private func targetNames(_ targets: [SessionTarget]) -> String {
        let names = targets.map(targetLabel)
        if names.count <= 1 {
            return names.first ?? "your selected targets"
        }
        if names.count == 2 {
            return names.joined(separator: " and ")
        }
        return names.dropLast().joined(separator: ", ")
            + ", and "
            + (names.last ?? "")
    }

    private func targetLabel(_ target: SessionTarget) -> String {
        targetPresentation(target).label
    }

    private func targetPresentation(
        _ target: SessionTarget
    ) -> TargetPresentation {
        switch target {
        case let .application(application):
            TargetPresentation(
                label: application.displayName,
                reviewTitle: "Entire application",
                reviewValue: application.displayName,
                systemImage: "macwindow",
                isBroadApplication: true
            )
        case let .window(window):
            TargetPresentation(
                label: "\(window.title) in \(window.application.displayName)",
                reviewTitle: "Individual window in \(window.application.displayName)",
                reviewValue: window.title,
                systemImage: "macwindow.on.rectangle",
                isBroadApplication: false
            )
        }
    }

    private struct TargetPresentation {
        let label: String
        let reviewTitle: String
        let reviewValue: String
        let systemImage: String
        let isBroadApplication: Bool
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
        VStack(spacing: 5) {
            HStack {
                Text("⌃⌥⌘S opens StayPane")
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
            Text("Menu-bar and in-app status work without notification permission.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
