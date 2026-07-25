import AppKit
import SwiftUI

@MainActor
final class StayPaneAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: (any StayPaneTerminationHandling)?
    private var isSystemPowerOffPending = false
    private weak var interfaceModel: StayPaneModel?
    private weak var floatingTimerPreferences: FloatingTimerPreferenceModel?
    private weak var launchAtLoginModel: LaunchAtLoginModel?
    private var floatingTimerController: FloatingTimerController?
    private var panelController: StayPanePanelController?
    private var openPanelShortcutController: OpenPanelShortcutController?
    private var auxiliaryWindowControllers: [
        StayPaneAuxiliaryWindow: StayPaneAuxiliaryWindowController
    ] = [:]

    func configure(
        model: StayPaneModel,
        floatingTimerPreferences: FloatingTimerPreferenceModel,
        launchAtLoginModel: LaunchAtLoginModel
    ) {
        self.model = model
        interfaceModel = model
        self.floatingTimerPreferences = floatingTimerPreferences
        self.launchAtLoginModel = launchAtLoginModel
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceWillPowerOff(_:)),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard let model else {
            return .terminateNow
        }
        if isSystemPowerOffPending {
            model.prepareForSystemTermination()
            return .terminateNow
        }
        return model.handleQuitRequest() ? .terminateNow : .terminateCancel
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let interfaceModel,
              let floatingTimerPreferences,
              let launchAtLoginModel
        else {
            return
        }

        let panelController = StayPanePanelController(
            model: interfaceModel,
            floatingTimerPreferences: floatingTimerPreferences,
            launchAtLoginModel: launchAtLoginModel
        )
        self.panelController = panelController
        floatingTimerController = FloatingTimerController(
            model: interfaceModel,
            preferences: floatingTimerPreferences
        )
        openPanelShortcutController = OpenPanelShortcutController {
            panelController.showPanel()
        }
        if openPanelShortcutController == nil {
            interfaceModel.showNotice(
                "The ⌃⌥⌘S shortcut is already in use, but the menu-bar panel remains available."
            )
        }
        panelController.showPanel()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showPanel()
        return true
    }

    func showPanel() {
        panelController?.showPanel()
    }

    func closePanel() {
        panelController?.closePanel()
    }

    func showAuxiliaryWindow(_ kind: StayPaneAuxiliaryWindow) {
        guard let interfaceModel,
              let floatingTimerPreferences,
              let launchAtLoginModel
        else {
            return
        }
        if let existing = auxiliaryWindowControllers[kind] {
            existing.present()
            return
        }

        let controller: StayPaneAuxiliaryWindowController
        switch kind {
        case .settings:
            controller = StayPaneAuxiliaryWindowController(
                title: "StayPane Settings",
                contentSize: CGSize(width: 620, height: 500),
                minimumContentSize: CGSize(width: 540, height: 420),
                rootView: AnyView(
                    StayPaneSettingsView(
                        model: interfaceModel,
                        floatingTimerPreferences: floatingTimerPreferences,
                        launchAtLoginModel: launchAtLoginModel
                    )
                )
            )
        case .help:
            controller = StayPaneAuxiliaryWindowController(
                title: "StayPane Setup & Help",
                contentSize: CGSize(width: 680, height: 650),
                minimumContentSize: CGSize(width: 560, height: 480),
                rootView: AnyView(
                    StayPaneHelpView(model: interfaceModel)
                )
            )
        case .history:
            controller = StayPaneAuxiliaryWindowController(
                title: "StayPane Session History",
                contentSize: CGSize(width: 620, height: 520),
                minimumContentSize: CGSize(width: 500, height: 380),
                rootView: AnyView(
                    StayPaneHistoryView(model: interfaceModel)
                )
            )
        }
        auxiliaryWindowControllers[kind] = controller
        controller.present()
    }

    func performPrimarySessionAction() {
        guard let interfaceModel else {
            return
        }
        switch presentationState(for: interfaceModel) {
        case .review:
            guard interfaceModel.canReview else {
                return
            }
            interfaceModel.startCountdown()
        case .setup:
            guard interfaceModel.canReview else {
                return
            }
            interfaceModel.beginReview()
        case .onboarding, .countdown, .recovering, .active, .resetPending,
             .completed, .endedEarly, .interrupted:
            break
        }
    }

    func cancelSessionNavigation() {
        guard let interfaceModel else {
            return
        }
        switch presentationState(for: interfaceModel) {
        case .review:
            interfaceModel.isReviewing = false
        case .countdown:
            interfaceModel.cancelCountdown()
        case .onboarding, .setup, .recovering, .active, .resetPending,
             .completed, .endedEarly, .interrupted:
            break
        }
    }

    private func presentationState(
        for model: StayPaneModel
    ) -> StayPaneSessionPresentationState {
        StayPaneSessionPresentationState.resolve(
            state: model.state,
            isReviewing: model.isReviewing,
            isOnboardingPresented: model.shouldPresentOnboarding
        )
    }

    @objc
    func workspaceWillPowerOff(_ notification: Notification) {
        isSystemPowerOffPending = true
    }
}

@main
@MainActor
struct StayPaneApp: App {
    @NSApplicationDelegateAdaptor(StayPaneAppDelegate.self) private var appDelegate
    @StateObject private var model: StayPaneModel
    @StateObject private var floatingTimerPreferences: FloatingTimerPreferenceModel
    @StateObject private var launchAtLoginModel: LaunchAtLoginModel

    init() {
        let model = StayPaneModel()
        let floatingTimerPreferences = FloatingTimerPreferenceModel()
        let launchAtLoginModel = LaunchAtLoginModel()
        _model = StateObject(wrappedValue: model)
        _floatingTimerPreferences = StateObject(
            wrappedValue: floatingTimerPreferences
        )
        _launchAtLoginModel = StateObject(wrappedValue: launchAtLoginModel)
        appDelegate.configure(
            model: model,
            floatingTimerPreferences: floatingTimerPreferences,
            launchAtLoginModel: launchAtLoginModel
        )
    }

    var body: some Scene {
        MenuBarExtra {
            StayPaneMenuBarView(
                model: model,
                floatingTimerPreferences: floatingTimerPreferences,
                openStatusPanel: {
                    appDelegate.showPanel()
                }
            )
        } label: {
            Label(model.menuBarTitle, systemImage: "rectangle.inset.filled.and.person.filled")
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.showAuxiliaryWindow(.settings)
                }
                .keyboardShortcut(",")
            }
            CommandGroup(after: .windowArrangement) {
                Button("Session History") {
                    appDelegate.showAuxiliaryWindow(.history)
                }
                Button("Setup & Help") {
                    appDelegate.showAuxiliaryWindow(.help)
                }
                .keyboardShortcut("?")
            }
            CommandMenu("Session") {
                Button("Find Targets") {
                    appDelegate.showPanel()
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .stayPaneFocusTargetSearch,
                            object: nil
                        )
                    }
                }
                .keyboardShortcut("f")

                Button(
                    model.isReviewing
                        ? "Start Session"
                        : "Review Session"
                ) {
                    appDelegate.performPrimarySessionAction()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!canPerformPrimarySessionAction)

                Button("Back or Cancel Countdown") {
                    appDelegate.cancelSessionNavigation()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!sessionPresentationState.supportsCancelNavigation)
            }
            CommandGroup(replacing: .appTermination) {
                Button("Quit StayPane") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }

    private var canPerformPrimarySessionAction: Bool {
        sessionPresentationState.supportsPrimaryAction && model.canReview
    }

    private var sessionPresentationState: StayPaneSessionPresentationState {
        StayPaneSessionPresentationState.resolve(
            state: model.state,
            isReviewing: model.isReviewing,
            isOnboardingPresented: model.shouldPresentOnboarding
        )
    }
}
