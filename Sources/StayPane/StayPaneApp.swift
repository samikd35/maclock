import AppKit
import SwiftUI

@MainActor
final class StayPaneAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: (any StayPaneTerminationHandling)?
    private var isSystemPowerOffPending = false
    private weak var interfaceModel: StayPaneModel?
    private weak var floatingTimerPreferences: FloatingTimerPreferenceModel?
    private var floatingTimerController: FloatingTimerController?
    private var panelController: StayPanePanelController?
    private var openPanelShortcutController: OpenPanelShortcutController?

    func configure(
        model: StayPaneModel,
        floatingTimerPreferences: FloatingTimerPreferenceModel
    ) {
        self.model = model
        interfaceModel = model
        self.floatingTimerPreferences = floatingTimerPreferences
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
        guard let interfaceModel, let floatingTimerPreferences else {
            return
        }

        let panelController = StayPanePanelController(
            model: interfaceModel,
            floatingTimerPreferences: floatingTimerPreferences
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
            panelController.showPanel()
        }
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

    init() {
        let model = StayPaneModel()
        let floatingTimerPreferences = FloatingTimerPreferenceModel()
        _model = StateObject(wrappedValue: model)
        _floatingTimerPreferences = StateObject(
            wrappedValue: floatingTimerPreferences
        )
        appDelegate.configure(
            model: model,
            floatingTimerPreferences: floatingTimerPreferences
        )
    }

    var body: some Scene {
        MenuBarExtra {
            StayPaneMenuView(
                model: model,
                floatingTimerPreferences: floatingTimerPreferences
            )
        } label: {
            Label(model.menuBarTitle, systemImage: "rectangle.inset.filled.and.person.filled")
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit StayPane") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}
