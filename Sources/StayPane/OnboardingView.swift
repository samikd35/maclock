import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: StayPaneModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to StayPane")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Stay with what you chose.")
                    .font(.headline)
                Text(
                    "This first-run checklist explains what StayPane can enforce, how its local permissions are used, and which browser setup is optional."
                )
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .contain)
            .accessibilitySortPriority(5)

            onboardingPrinciples
                .accessibilitySortPriority(4)
            accessibilitySetup
                .accessibilitySortPriority(3)
            chromeSetup
                .accessibilitySortPriority(2)
            notificationAndFocusGuidance
                .accessibilitySortPriority(1)

            Button("Continue to Session Setup") {
                model.finishOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .disabled(!model.onboardingChecklist.canFinish)
            .accessibilityHint(
                model.onboardingChecklist.canFinish
                    ? "Closes the first-run checklist."
                    : "First verify Accessibility using the harmless window-control test."
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("StayPane first-run onboarding")
    }

    private var onboardingPrinciples: some View {
        VStack(alignment: .leading, spacing: 9) {
            checklistHeading(
                "Honest boundary and local privacy",
                status: .complete
            )
            Text(
                "StayPane is an honest self-control tool, not tamper-proof security. Force Quit, administrator changes, source modification, permission revocation, and disabling the Chrome companion remain deliberate bypasses. If reliable enforcement disappears, StayPane uses Fail Open and restores what it can."
            )
            .font(.subheadline)
            Text(
                "Your Session state, minimal History, redacted Diagnostics, window details, and optional browser messages stay on this Mac. StayPane has no account, cloud service, analytics, telemetry, automatic crash upload, or background update check."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onboardingCard(background: cardBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Honest boundary and local privacy, complete")
    }

    private var accessibilitySetup: some View {
        let state = model.accessibilitySetupState
        return VStack(alignment: .leading, spacing: 9) {
            checklistHeading(
                "Accessibility setup",
                status: model.onboardingChecklist.accessibilityStatus
            )
            Label(state.title, systemImage: accessibilityImage(state))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accessibilityColor(state))
            Text(
                "StayPane uses macOS Accessibility only to discover, minimize, restore, and refocus windows. The Harmless Window-Control Verification writes a window's existing minimized value back unchanged; it does not move, resize, close, or reveal content. Screen Recording is never requested."
            )
            .font(.caption)
            Text(state.guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                if state != .verified {
                    Button("Open Accessibility Settings") {
                        model.requestAccessibilityAccess()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint(
                        "Requests Accessibility permission and opens Privacy and Security settings."
                    )
                }
                Button(
                    state == .verified
                        ? "Repeat Harmless Window-Control Verification"
                        : "Run Harmless Window-Control Verification"
                ) {
                    model.runHarmlessWindowControlTest()
                }
                .buttonStyle(.bordered)
                .accessibilityHint(
                    "Verifies window control without changing window layout or content."
                )
            }
        }
        .onboardingCard(background: cardBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Accessibility setup, \(state.title)")
    }

    private var chromeSetup: some View {
        let state = model.chromeSetupState
        return VStack(alignment: .leading, spacing: 9) {
            checklistHeading(
                "Chrome setup — optional",
                status: model.onboardingChecklist.chromeStatus
            )
            Label(state.title, systemImage: chromeImage(state))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(chromeColor(state))
            Text(
                "Skip this for native Application Targets and Window Targets. The local companion is required only when you choose a Browser Window Target or Tab Target. No Google developer account or Chrome Web Store listing is needed."
            )
            .font(.caption)
            Text(state.guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(
                "Setup: register the Native Host, load the built extension with Developer Mode → Load unpacked, enable Allow in Incognito, then test the connection. Incognito tabs remain unselectable."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            HStack {
                Button(
                    model.nativeHostRegistered
                        ? "Repair Native Host"
                        : "Register Native Host"
                ) {
                    model.registerNativeHost()
                }
                .buttonStyle(.bordered)
                Button("Show Extension Folder") {
                    model.openChromeExtensionFolder()
                }
                .buttonStyle(.bordered)
            }
            HStack {
                Button("Test Connection") {
                    model.testChromeConnection()
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
        .onboardingCard(background: cardBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Optional Chrome setup, \(state.title)")
    }

    private var notificationAndFocusGuidance: some View {
        VStack(alignment: .leading, spacing: 8) {
            checklistHeading("Completion and notifications", status: .complete)
            Text(
                "Notification permission is optional. If notifications are denied, the Status Panel still shows Session Complete and the menu-bar title briefly changes to Session Complete."
            )
            .font(.caption)
            Text(
                "StayPane cannot reliably enable macOS Focus automatically. Final Session review includes an optional reminder and a button to open Focus Settings if you want other app notifications silenced."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onboardingCard(background: cardBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Completion and notification guidance, complete")
    }

    private func checklistHeading(
        _ title: String,
        status: OnboardingChecklistStatus
    ) -> some View {
        Label(title, systemImage: checklistImage(status))
            .font(.headline)
            .foregroundStyle(checklistColor(status))
            .accessibilityAddTraits(.isHeader)
    }

    private var cardBackground: Color {
        .secondary.opacity(
            VisualAccessibilityPolicy(
                increasedContrast: contrast == .increased
            ).cardOpacity(standardOpacity: 0.08)
        )
    }

    private func checklistImage(_ status: OnboardingChecklistStatus) -> String {
        switch status {
        case .complete:
            "checkmark.circle.fill"
        case .needsAttention:
            "exclamationmark.triangle.fill"
        case .inProgress:
            "arrow.triangle.2.circlepath"
        case .optional:
            "circle.dashed"
        }
    }

    private func checklistColor(_ status: OnboardingChecklistStatus) -> Color {
        switch status {
        case .complete:
            .green
        case .needsAttention:
            .orange
        case .inProgress:
            .blue
        case .optional:
            .secondary
        }
    }

    private func accessibilityImage(_ state: AccessibilitySetupState) -> String {
        state == .verified
            ? "checkmark.seal.fill"
            : "hand.raised.fill"
    }

    private func accessibilityColor(_ state: AccessibilitySetupState) -> Color {
        state == .verified ? .green : .orange
    }

    private func chromeImage(_ state: ChromeSetupState) -> String {
        if case .ready = state {
            return "link.circle.fill"
        }
        return "puzzlepiece.extension"
    }

    private func chromeColor(_ state: ChromeSetupState) -> Color {
        if case .ready = state {
            return .green
        }
        if state == .nativeHostNotRegistered {
            return .secondary
        }
        return .orange
    }
}

private extension View {
    func onboardingCard(background: Color) -> some View {
        padding(12)
            .background(background, in: RoundedRectangle(cornerRadius: 10))
    }
}
