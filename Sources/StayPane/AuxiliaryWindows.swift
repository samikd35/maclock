import AppKit
import StayPaneCore
import SwiftUI

enum StayPaneAuxiliaryWindow: String, Hashable {
    case settings
    case help
    case history
}

@MainActor
final class StayPaneAuxiliaryWindowController: NSWindowController {
    init(
        title: String,
        contentSize: CGSize,
        minimumContentSize: CGSize,
        rootView: AnyView
    ) {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable
            ],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentMinSize = minimumContentSize
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum StayPaneWindowRouter {
    @MainActor
    static func open(_ window: StayPaneAuxiliaryWindow) {
        guard let delegate = NSApplication.shared.delegate
                as? StayPaneAppDelegate
        else {
            return
        }
        delegate.showAuxiliaryWindow(window)
    }
}

struct StayPaneSettingsView: View {
    @ObservedObject var model: StayPaneModel
    @ObservedObject var floatingTimerPreferences: FloatingTimerPreferenceModel
    @ObservedObject var launchAtLoginModel: LaunchAtLoginModel

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            integrationsSettings
                .tabItem {
                    Label("Integrations", systemImage: "puzzlepiece.extension")
                }
            recoverySettings
                .tabItem {
                    Label("Recovery", systemImage: "arrow.clockwise.circle")
                }
            privacySettings
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var generalSettings: some View {
        Form {
            Section("Floating Timer") {
                Toggle(
                    "Show during an active Session",
                    isOn: Binding(
                        get: {
                            floatingTimerPreferences.value.isVisible
                        },
                        set: {
                            floatingTimerPreferences.setVisible($0)
                        }
                    )
                )
                Toggle(
                    "Start collapsed",
                    isOn: Binding(
                        get: {
                            floatingTimerPreferences.value.isCollapsed
                        },
                        set: {
                            floatingTimerPreferences.setCollapsed($0)
                        }
                    )
                )

                HStack {
                    Text("Size")
                    Slider(
                        value: Binding(
                            get: {
                                floatingTimerPreferences.value.scale
                            },
                            set: {
                                floatingTimerPreferences.setScale($0)
                            }
                        ),
                        in: 0...1
                    )
                    Text(floatingTimerPreferences.sizeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }

                HStack {
                    Button("Reset to Medium") {
                        floatingTimerPreferences.resetScale()
                    }
                    Button("Move to Top Right") {
                        floatingTimerPreferences.resetPosition()
                    }
                }
            }

            Section {
                Text(
                    "Resize the Floating Timer directly from any edge or corner. Its position, size, and collapsed state stay local to this Mac."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var integrationsSettings: some View {
        Form {
            Section("Accessibility") {
                LabeledContent(
                    "Status",
                    value: model.accessibilitySetupState.title
                )
                HStack {
                    Button("Open Accessibility Settings") {
                        model.requestAccessibilityAccess()
                    }
                    Button("Check Again") {
                        model.refreshAccessibilityStatus()
                    }
                    Button("Harmless Verification") {
                        model.runHarmlessWindowControlTest()
                    }
                }
            }

            Section("Chrome companion") {
                LabeledContent(
                    "Status",
                    value: model.chromeSetupState.title
                )
                HStack {
                    Button(model.nativeHostRegistrationActionTitle) {
                        model.registerNativeHost()
                    }
                    Button("Show Extension Folder") {
                        model.openChromeExtensionFolder()
                    }
                    Button("Test Connection") {
                        model.testChromeConnection()
                    }
                }
                Text(
                    "Required only for Browser Window Targets and Tab Targets."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var recoverySettings: some View {
        Form {
            Section("Launch at Login") {
                Toggle(
                    "Launch StayPane after login",
                    isOn: Binding(
                        get: { launchAtLoginModel.presentation.isOn },
                        set: { launchAtLoginModel.setEnabled($0) }
                    )
                )
                .disabled(!launchAtLoginModel.presentation.isInteractive)
                Text(launchAtLoginModel.presentation.guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if launchAtLoginModel.presentation.showsSettingsAction {
                    Button("Open Login Items Settings") {
                        launchAtLoginModel.openSystemSettings()
                    }
                }
            }

            Section {
                Text(
                    "An unfinished Session keeps its Fixed End Time. Launch at Login lets StayPane attempt Recovery automatically after logout or restart."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLoginModel.refresh()
        }
    }

    private var privacySettings: some View {
        Form {
            Section("Local-only data") {
                Text(
                    "Session state, bounded Session History, redacted Diagnostics, window identities, and optional browser messages stay on this Mac. StayPane has no account, cloud service, analytics, telemetry, or automatic diagnostic upload."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Actions") {
                HStack {
                    Button("Open Session History") {
                        StayPaneWindowRouter.open(.history)
                    }
                    Button("Export Diagnostics…") {
                        model.exportDiagnostics()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct StayPaneHelpView: View {
    @ObservedObject var model: StayPaneModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Setup & Help")
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                helpSection(
                    title: "Honest self-control",
                    systemImage: "lock.open"
                ) {
                    Text(
                        "StayPane is not tamper-proof security. Force Quit, administrator changes, permission revocation, source changes, and disabling the Chrome companion remain deliberate bypasses. If reliable enforcement disappears, StayPane uses Fail Open and restores what it can."
                    )
                }

                helpSection(
                    title: "Accessibility",
                    systemImage: "hand.raised"
                ) {
                    Text(
                        "Accessibility lets StayPane discover, minimize, restore, and refocus app windows. It never reads window pixels and never requests Screen Recording. After moving from the development build, remove its old .build entry if present and authorize ~/Applications/StayPane.app."
                    )
                    Text(model.accessibilitySetupState.guidance)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Open Settings") {
                            model.requestAccessibilityAccess()
                        }
                        Button("Run Harmless Verification") {
                            model.runHarmlessWindowControlTest()
                        }
                    }
                }

                helpSection(
                    title: "Chrome companion",
                    systemImage: "puzzlepiece.extension"
                ) {
                    Text(
                        "Skip this for native Application Targets and Window Targets. Browser Window Targets and Tab Targets require the local Native Host and unpacked extension. No Google developer account or Chrome Web Store listing is required."
                    )
                    Text(
                        "In chrome://extensions, enable Developer Mode, load the built extension folder, open its Details, and enable Allow in Incognito. Incognito tabs remain unselectable."
                    )
                    .foregroundStyle(.secondary)
                    HStack {
                        Button(model.nativeHostRegistrationActionTitle) {
                            model.registerNativeHost()
                        }
                        Button("Show Extension Folder") {
                            model.openChromeExtensionFolder()
                        }
                        Button("Test Connection") {
                            model.testChromeConnection()
                        }
                    }
                }

                helpSection(
                    title: "Keyboard",
                    systemImage: "keyboard"
                ) {
                    Text("⌃⌥⌘S opens StayPane from anywhere.")
                    Text("⌘F searches Targets. ⌘Return reviews or starts. Escape goes back or cancels the countdown. ⌘, opens Settings.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }

    private func helpSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }
}

struct StayPaneHistoryView: View {
    @ObservedObject var model: StayPaneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Session History")
                        .font(.title2.weight(.semibold))
                    Text("Bounded and stored only on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear Session History…", role: .destructive) {
                    model.requestHistoryClear()
                }
                .disabled(model.sessionHistory.isEmpty)
            }

            if model.sessionHistory.isEmpty {
                ContentUnavailableView(
                    "No Session History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(
                        "Completed, ended-early, and interrupted Sessions appear here without Target details."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(
                    Array(model.sessionHistory.reversed().enumerated()),
                    id: \.offset
                ) { _, record in
                    historyRow(record)
                }
            }

            HStack {
                Text(
                    "Session History never stores application, window, tab, URL, or domain details."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Export Diagnostics…") {
                    model.exportDiagnostics()
                }
            }
        }
        .padding(20)
        .confirmationDialog(
            StayPaneAccessibilityText.clearHistoryConfirmation,
            isPresented: Binding(
                get: { model.isConfirmingHistoryClear },
                set: {
                    if !$0 {
                        model.cancelHistoryClear()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(
                StayPaneAccessibilityText.clearHistoryAction,
                role: .destructive
            ) {
                model.confirmHistoryClear()
            }
            Button("Cancel", role: .cancel) {
                model.cancelHistoryClear()
            }
        } message: {
            Text(StayPaneAccessibilityText.clearHistoryWarning)
        }
    }

    private func historyRow(
        _ record: SessionHistoryRecord
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(resultLabel(record.result))
                    .font(.headline)
                Spacer()
                Text(
                    record.startedAt,
                    format: .dateTime.year().month().day().hour().minute()
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Text(
                "Planned \(StayPaneModel.formatPreset(seconds: record.plannedDuration.seconds)) · Focused \(StayPaneModel.formatPreset(seconds: max(0, Int(record.actualFocusTime.rounded()))))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func resultLabel(_ result: SessionResult) -> String {
        switch result {
        case .completed:
            "Completed"
        case .endedEarly:
            "Ended Early"
        case .interrupted:
            "Interrupted"
        }
    }
}
