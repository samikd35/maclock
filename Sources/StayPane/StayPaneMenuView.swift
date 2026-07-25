import AppKit
import StayPaneCore
import SwiftUI

struct StayPaneMenuView: View {
    @ObservedObject var model: StayPaneModel
    @ObservedObject var floatingTimerPreferences: FloatingTimerPreferenceModel
    @ObservedObject var launchAtLoginModel: LaunchAtLoginModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var applicationSearchText = ""
    @State private var healthPopoverPresented = false
    @State private var reviewDetailsExpanded = false
    @State private var activeTargetsExpanded = false

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            StayPaneAccessibilityText.clearHistoryConfirmation,
            isPresented: Binding(
                get: { model.isConfirmingHistoryClear },
                set: { isPresented in
                    if !isPresented {
                        model.cancelHistoryClear()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(StayPaneAccessibilityText.clearHistoryAction, role: .destructive) {
                model.confirmHistoryClear()
            }
            Button("Cancel", role: .cancel) {
                model.cancelHistoryClear()
            }
        } message: {
            Text(StayPaneAccessibilityText.clearHistoryWarning)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.statusPanelAccessibilityPresentation.title)
        .accessibilityValue(
            model.statusPanelAccessibilityPresentation.announcement
        )
        .onChange(of: model.statusPanelAccessibilityPresentation) { _, value in
            AccessibilityAnnouncer.announce(value.announcement)
        }
        .onChange(of: healthSummary) { _, summary in
            if summary.severity == .blocking {
                AccessibilityAnnouncer.announce(
                    "Session setup blocked. \(summary.title)"
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.title2)
                .foregroundStyle(.tint)
            Text(panelPresentation.title)
                .font(.headline)
            Spacer()
            if panelPresentation == .setup || panelPresentation == .review {
                Button {
                    healthPopoverPresented.toggle()
                } label: {
                    Label(
                        healthSummary.title,
                        systemImage: healthSystemImage
                    )
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderless)
                .foregroundStyle(healthColor)
                .popover(isPresented: $healthPopoverPresented) {
                    setupHealthPopover
                }
                .accessibilityLabel(
                    "Setup health, \(healthSummary.title)"
                )
            }
            Button {
                StayPaneWindowRouter.open(.help)
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Open Setup & Help")
            .accessibilityLabel("Open Setup and Help")

            Button {
                StayPaneWindowRouter.open(.settings)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Open Settings")
            .accessibilityLabel("Open Settings")
        }
        .padding(14)
    }

    private var panelPresentation: StayPanePanelPresentation {
        StayPanePanelPresentation.resolve(
            state: model.state,
            isReviewing: model.isReviewing,
            isOnboardingPresented: model.shouldPresentOnboarding
        )
    }

    private var setupHealthPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(healthSummary.title, systemImage: healthSystemImage)
                .font(.headline)
                .foregroundStyle(healthColor)

            healthRow(
                title: "Accessibility",
                value: model.accessibilitySetupState.title,
                isReady: model.accessibilityGranted
            ) {
                Button("Open Settings") {
                    model.requestAccessibilityAccess()
                }
                Button("Check Again") {
                    model.refreshAccessibilityStatus()
                }
            }

            if showsChromeCompanionSetup {
                healthRow(
                    title: "Chrome companion",
                    value: model.chromeSetupState.title,
                    isReady: browserIntegrationReady
                ) {
                    Button(
                        model.nativeHostRegistered
                            ? "Repair Native Host"
                            : "Register Native Host"
                    ) {
                        model.registerNativeHost()
                    }
                    Button("Instructions") {
                        StayPaneWindowRouter.open(.help)
                        healthPopoverPresented = false
                    }
                }
            }

            healthRow(
                title: "Recovery",
                value: launchAtLoginModel.presentation.statusTitle,
                isReady: launchAtLoginModel.isEffective
            ) {
                if launchAtLoginModel.presentation.showsSettingsAction {
                    Button("Open Login Items") {
                        launchAtLoginModel.openSystemSettings()
                    }
                }
            }

            Divider()
            Button("Open Setup & Help") {
                StayPaneWindowRouter.open(.help)
                healthPopoverPresented = false
            }
        }
        .padding(16)
        .frame(width: 330)
    }

    private func healthRow<Actions: View>(
        title: String,
        value: String,
        isReady: Bool,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(
                    title,
                    systemImage: isReady
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                Spacer()
                Text(value)
                    .font(.caption)
                    .foregroundStyle(isReady ? .green : .orange)
            }
            HStack(spacing: 8) {
                actions()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var healthSummary: SetupHealthSummary {
        SetupHealthSummary.resolve(
            accessibilityReady: model.accessibilityGranted,
            browserTargetsSelected: showsChromeCompanionSetup,
            browserReady: browserIntegrationReady,
            recoveryReady: launchAtLoginModel.isEffective
        )
    }

    private var browserIntegrationReady: Bool {
        !model.selectedBrowserProfiles.isEmpty
            && model.selectedBrowserProfiles.allSatisfy {
                $0.availability == .ready
            }
    }

    private var healthSystemImage: String {
        switch healthSummary.severity {
        case .ready:
            "checkmark.seal.fill"
        case .attention:
            "exclamationmark.circle.fill"
        case .blocking:
            "exclamationmark.triangle.fill"
        }
    }

    private var healthColor: Color {
        switch healthSummary.severity {
        case .ready:
            .green
        case .attention:
            .orange
        case .blocking:
            .red
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.shouldPresentOnboarding {
            OnboardingView(model: model)
        } else if model.isReviewing {
            reviewView
        } else {
            switch model.state {
            case .idle, .configuring, .ready:
                setupView
            case let .starting(plan, _):
                countdownView(plan: plan)
            case let .recovering(recoveringSession):
                recoveringView(recoveringSession: recoveringSession)
            case let .enforcing(activeSession):
                enforcingView(activeSession: activeSession)
            case let .resetPending(pendingReset):
                resetPendingView(pendingReset: pendingReset)
            case let .completed(completedSession):
                completedView(completedSession: completedSession)
            case let .endedEarly(endedSession):
                endedEarlyView(endedSession: endedSession)
            case let .interrupted(interruptedSession):
                interruptedView(interruptedSession: interruptedSession)
            }
        }
    }

    private func recoveringView(
        recoveringSession: RecoveringSession
    ) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Resuming Session")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("StayPane is verifying the saved Tab Target before restoring enforcement.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text(
                "Fixed end time: \(recoveringSession.activeSession.endsAt.formatted(date: .omitted, time: .shortened))"
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 35)
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Focus duration")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                ClockDurationEditor(
                    totalSeconds: Binding(
                        get: { model.durationSeconds },
                        set: { seconds in
                            model.durationSeconds = seconds
                            model.updateDuration()
                        }
                    ),
                    validationMessage: Binding(
                        get: { model.durationValidationMessage },
                        set: {
                            model.setDurationDraftValidationMessage($0)
                        }
                    )
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("What stays available")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(StayPaneAccessibilityText.targetRegionGuidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TargetPickerView(
                    model: model,
                    searchText: $applicationSearchText
                )

                if model.selectedApplicationIDs.contains("com.google.Chrome") {
                    broadChromeApplicationWarning
                } else if !model.selectedApplicationIDs.isEmpty {
                    broadApplicationWarning
                }
                if !model.selectedWindowIDs.isEmpty {
                    preciseWindowNote
                }
                if !model.selectedBrowserWindowIDs.isEmpty {
                    broadChromeWindowWarning
                }
                if !model.selectedBrowserTabIDs.isEmpty {
                    preciseBrowserTabNote
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                StayPaneAccessibilityText.targetHierarchyRegion
            )

        }
    }

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "\(StayPaneModel.formatPreset(seconds: model.durationSeconds)) · \(model.configuredTargets.count) Target\(model.configuredTargets.count == 1 ? "" : "s")"
                )
                .font(.largeTitle.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                Text(
                    "The duration and Allowlist become immutable when the three-second countdown finishes."
                )
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Allowlist")
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
                guard case let .application(application) = $0 else {
                    return false
                }
                return model.isChromeApplication(
                    application.bundleIdentifier
                )
            }) {
                broadChromeApplicationWarning
            } else if model.configuredTargets.contains(where: {
                targetPresentation($0).isBroadApplication
            }) {
                broadApplicationWarning
            }
            if model.configuredTargets.contains(where: {
                if case .window = $0 { return true }
                return false
            }) {
                preciseWindowNote
            }
            if model.configuredTargets.contains(where: {
                if case .browserWindow = $0 { return true }
                return false
            }) {
                broadChromeWindowWarning
            }

            DisclosureGroup(
                "Session details",
                isExpanded: $reviewDetailsExpanded
            ) {
                VStack(alignment: .leading, spacing: 9) {
                    reviewRow(
                        title: "Accessibility",
                        value: model.accessibilityGranted
                            ? "Verified"
                            : "Missing",
                        systemImage: model.accessibilityGranted
                            ? "checkmark.seal"
                            : "exclamationmark.triangle"
                    )
                    reviewRow(
                        title: "Floating Timer",
                        value: floatingTimerPreferenceSummary,
                        systemImage: "timer"
                    )
                    reviewRow(
                        title: "Recovery",
                        value: launchAtLoginModel.presentation.statusTitle,
                        systemImage: launchAtLoginModel.isEffective
                            ? "checkmark.circle"
                            : "exclamationmark.triangle"
                    )
                    if !launchAtLoginModel.isEffective {
                        restartRecoveryNotice
                    }
                    Button("Open optional macOS Focus settings") {
                        if !FocusSettingsOpener.open() {
                            model.showNotice(
                                "Open System Settings → Focus to silence notifications during a Session."
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    Text(
                        "StayPane does not toggle macOS Focus or automate Control Center."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
            .padding(10)
            .background(
                adaptiveBackground(.secondary, opacity: 0.08),
                in: RoundedRectangle(cornerRadius: 8)
            )

            HStack {
                Button("Back") {
                    model.isReviewing = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(
                    "Start \(StayPaneModel.formatPreset(seconds: model.durationSeconds)) Session"
                ) {
                    model.startCountdown()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func countdownView(plan: SessionPlan) -> some View {
        VStack(spacing: 18) {
            Text("Starting focus session")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("\(model.countdownNumber)")
                .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                .contentTransition(countdownContentTransition)
                .accessibilityLabel(
                    "Session starts in \(model.countdownNumber) seconds"
                )
            Text("Only \(targetNames(plan.targets)) will remain available for \(model.formattedDuration).")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Cancel countdown") {
                model.cancelCountdown()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 35)
    }

    private func enforcingView(activeSession: ActiveSession) -> some View {
        VStack(spacing: 16) {
            Label("Locked", systemImage: "lock.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)
                .accessibilityAddTraits(.isHeader)

            Text(model.formattedRemainingTime)
                .font(.system(size: 62, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(countdownContentTransition)
                .accessibilityLabel(
                    "\(model.formattedRemainingTime) remaining"
                )

            VStack(spacing: 8) {
                Text(
                    "Ends \(activeSession.endsAt.formatted(date: .omitted, time: .shortened))"
                )
                .font(.headline.monospacedDigit())

                ProgressView(value: activeSessionProgress(activeSession))
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Session progress")

                DisclosureGroup(
                    "\(activeSession.plan.targets.count) Target\(activeSession.plan.targets.count == 1 ? "" : "s") available",
                    isExpanded: $activeTargetsExpanded
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(
                            activeSession.plan.targets,
                            id: \.id
                        ) { target in
                            Label(
                                targetLabel(target),
                                systemImage: targetPresentation(
                                    target
                                ).systemImage
                            )
                            .font(.subheadline)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity)

            floatingTimerControls

            Button("End Session Early…", role: .destructive) {
                model.requestEarlyReset()
            }
            .buttonStyle(.bordered)

            honestBoundaryNote
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func activeSessionProgress(
        _ activeSession: ActiveSession
    ) -> Double {
        let total = max(
            1,
            activeSession.plan.duration.timeInterval
        )
        return min(max(1 - (model.remainingTime / total), 0), 1)
    }

    private func resetPendingView(pendingReset: ResetPendingSession) -> some View {
        VStack(spacing: 16) {
            Label("Early reset requested", systemImage: "hourglass")
                .font(.headline)
                .foregroundStyle(.orange)
                .accessibilityAddTraits(.isHeader)

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
                    .keyboardShortcut(.defaultAction)

                    Button("End session now", role: .destructive) {
                        model.confirmEarlyReset()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("\(model.earlyResetCountdownNumber)")
                    .font(.system(size: 62, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(countdownContentTransition)
                    .accessibilityLabel(
                        "\(model.earlyResetCountdownNumber) seconds until final Early Reset confirmation"
                    )
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
                .keyboardShortcut(.cancelAction)
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
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 16) {
                summaryMetric(
                    title: "Planned",
                    value: StayPaneModel.formatPreset(
                        seconds: completedSession.plan.duration.seconds
                    )
                )
                summaryMetric(
                    title: "Focused",
                    value: StayPaneModel.formatPreset(
                        seconds: completedSession.plan.duration.seconds
                    )
                )
            }
            restorationSummary
            nextSessionButtons
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
                .accessibilityAddTraits(.isHeader)
            Text("Outcome: Ended Early")
                .font(.headline)
            HStack(spacing: 16) {
                summaryMetric(
                    title: "Planned",
                    value: StayPaneModel.formatPreset(
                        seconds: endedSession.plan.duration.seconds
                    )
                )
                summaryMetric(
                    title: "Focused",
                    value: StayPaneModel.formatPreset(
                        seconds: Int(
                            endedSession.actualFocusDuration.rounded()
                        )
                    )
                )
            }
            restorationSummary
            nextSessionButtons
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 35)
    }

    private func interruptedView(
        interruptedSession: InterruptedSession
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
            Text("Session Interrupted")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("StayPane stopped enforcement and restored what remained controllable because reliable enforcement was lost.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text(interruptionExplanation(interruptedSession.reason))
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                summaryMetric(
                    title: "Planned",
                    value: StayPaneModel.formatPreset(
                        seconds: interruptedSession.plan.duration.seconds
                    )
                )
                summaryMetric(
                    title: "Focused",
                    value: StayPaneModel.formatPreset(
                        seconds: Int(
                            interruptedSession.actualFocusDuration.rounded()
                        )
                    )
                )
            }
            restorationSummary
            nextSessionButtons
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 35)
    }

    private func interruptionExplanation(
        _ reason: SessionInterruptionReason
    ) -> String {
        switch reason {
        case .enforcementUnavailable:
            "The complete Allowlist could no longer be enforced reliably."
        case .recoveryUnavailable:
            "StayPane could not safely resume the saved Session."
        }
    }

    private func summaryMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
        }
        .frame(minWidth: 100)
        .padding(10)
        .background(
            adaptiveBackground(.secondary, opacity: 0.08),
            in: RoundedRectangle(cornerRadius: 9)
        )
    }

    private var restorationSummary: some View {
        Label(
            model.pendingRestorationCount == 0
                ? "Restoration complete"
                : "\(model.pendingRestorationCount) window\(model.pendingRestorationCount == 1 ? "" : "s") still restoring",
            systemImage: model.pendingRestorationCount == 0
                ? "checkmark.circle.fill"
                : "arrow.clockwise.circle"
        )
        .font(.caption)
        .foregroundStyle(
            model.pendingRestorationCount == 0
                ? Color.green
                : Color.orange
        )
    }

    private var nextSessionButtons: some View {
        HStack {
            Button("New Session") {
                model.startNewSession()
            }
            .buttonStyle(.bordered)

            Button("Done") {
                (NSApplication.shared.delegate as? StayPaneAppDelegate)?
                    .closePanel()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Use Same Setup") {
                model.reuseLastSessionSetup()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
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
                            ? "Expand Floating Timer"
                            : "Collapse Floating Timer"
                    ) {
                        floatingTimerPreferences.toggleCollapsed()
                    }
                    .buttonStyle(.bordered)
                }
            }
            if floatingTimerPreferences.value.isVisible {
                HStack {
                    Button("Move to Top Right") {
                        floatingTimerPreferences.resetPosition()
                    }
                    .buttonStyle(.bordered)
                }
            }
            Text("The Floating Timer stays above work. Drag it to move, resize from any edge, and collapse or hide it without affecting the menu-bar countdown.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var floatingTimerPreferenceSummary: String {
        guard floatingTimerPreferences.value.isVisible else {
            return "Hidden; menu-bar countdown remains"
        }
        let state = floatingTimerPreferences.value.isCollapsed
            ? "collapsed"
            : "expanded"
        return "Visible, \(state), \(floatingTimerPreferences.sizeDescription.lowercased())"
    }

    private var broadApplicationWarning: some View {
        Label(
            StayPaneAccessibilityText.broadApplicationWarning,
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(.orange)
        .padding(10)
        .background(
            adaptiveBackground(.orange, opacity: 0.1),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .accessibilityLabel(
            StayPaneAccessibilityText.broadApplicationWarning
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
        .background(
            adaptiveBackground(.blue, opacity: 0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var preciseBrowserTabNote: some View {
        Label(
            "Each Tab Target keeps its own immutable Navigation Scope. Current Website allows HTTP and HTTPS pages on the chosen hostname. Exact Page also locks the path and query while ignoring fragments. Activating an unapproved, duplicated, or newly opened tab is a Blocked Tab Activation.",
            systemImage: "rectangle.stack.badge.person.crop"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(.blue)
        .padding(10)
        .background(
            adaptiveBackground(.blue, opacity: 0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var broadChromeApplicationWarning: some View {
        Label(
            StayPaneAccessibilityText.broadChromeApplicationWarning,
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(.orange)
        .padding(10)
        .background(
            adaptiveBackground(.orange, opacity: 0.1),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .accessibilityLabel(
            StayPaneAccessibilityText.broadChromeApplicationWarning
        )
    }

    private var broadChromeWindowWarning: some View {
        Label(
            "A Browser Window Target allows every current and future tab and website inside that Chrome window. Navigation Scopes do not apply; other Chrome windows remain blocked.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption.weight(.medium))
        .foregroundStyle(.orange)
        .padding(10)
        .background(
            adaptiveBackground(.orange, opacity: 0.1),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .accessibilityLabel(
            StayPaneAccessibilityText.broadChromeWindowWarning
        )
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
        case let .browserWindow(window):
            TargetPresentation(
                label: window.title,
                reviewTitle: "Browser Window Target",
                reviewValue: "\(window.title) — \(model.browserProfileLabel(window.profileIdentifier))",
                systemImage: "macwindow.on.rectangle",
                isBroadApplication: false
            )
        case let .browserTab(tab):
            TargetPresentation(
                label: "\(tab.title) (\(browserScopeName(tab.navigationScope))) in \(tab.application.displayName)",
                reviewTitle: "Individual Chrome tab",
                reviewValue: "\(tab.title) — \(model.browserProfileLabel(tab.profileIdentifier)) — \(browserScopeName(tab.navigationScope)): \(browserScopeValue(tab))",
                systemImage: "rectangle.stack",
                isBroadApplication: false
            )
        }
    }

    private func browserScopeName(_ scope: BrowserNavigationScope) -> String {
        switch scope {
        case .currentWebsite:
            "Current Website"
        case .exactPage:
            "Exact Page"
        }
    }

    private func browserScopeValue(_ tab: BrowserTabTarget) -> String {
        switch tab.navigationScope {
        case .currentWebsite:
            return tab.url.host ?? tab.url.absoluteString
        case .exactPage:
            guard let components = URLComponents(
                url: tab.url,
                resolvingAgainstBaseURL: false
            ) else {
                return tab.url.absoluteString
            }
            return (components.host ?? "")
                + components.path
                + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
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
        .background(
            adaptiveBackground(.secondary, opacity: 0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var footer: some View {
        VStack(spacing: 5) {
            if showsSetupReviewAction {
                HStack {
                    Text(
                        setupValidationSummary
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button(StayPaneAccessibilityText.reviewAction) {
                        model.beginReview()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canBeginReview)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var showsSetupReviewAction: Bool {
        !model.shouldPresentOnboarding
            && !model.isReviewing
            && panelPresentation == .setup
    }

    private var showsChromeCompanionSetup: Bool {
        !model.selectedBrowserWindowIDs.isEmpty
            || !model.selectedBrowserTabIDs.isEmpty
    }

    private var canBeginReview: Bool {
        model.canReview
    }

    private var setupValidationSummary: String {
        if model.durationValidationMessage != nil {
            return "Enter a valid Session duration"
        }
        return model.canReview
            ? "Ready for final review"
            : "Choose at least one Target"
    }

    @ViewBuilder
    private var restartRecoveryNotice: some View {
        if launchAtLoginModel.status != .enabled {
            Label(
                launchAtLoginModel.presentation.guidance,
                systemImage: "exclamationmark.arrow.triangle.2.circlepath"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityLabel(
                "Launch at Login, \(launchAtLoginModel.presentation.statusTitle). \(launchAtLoginModel.presentation.guidance)"
            )
        }
    }

    private var countdownContentTransition: ContentTransition {
        visualAccessibilityPolicy
            .usesAnimatedNumberTransitions
            ? .numericText()
            : .identity
    }

    private var visualAccessibilityPolicy: VisualAccessibilityPolicy {
        VisualAccessibilityPolicy(
            reduceMotion: reduceMotion,
            increasedContrast: contrast == .increased
        )
    }

    private func adaptiveBackground(
        _ color: Color,
        opacity: Double
    ) -> Color {
        color.opacity(
            visualAccessibilityPolicy.cardOpacity(
                standardOpacity: opacity
            )
        )
    }

}

private struct NoticeBanner: View {
    let message: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Label(message, systemImage: "info.circle.fill")
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                .orange.opacity(
                    VisualAccessibilityPolicy(
                        increasedContrast: contrast == .increased
                    ).cardOpacity(standardOpacity: 0.12)
                ),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .accessibilityLabel("StayPane status: \(message)")
            .onAppear {
                AccessibilityAnnouncer.announce(message)
            }
    }
}
