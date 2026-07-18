import AppKit
import SwiftUI

@MainActor
final class StayPanePanelController: NSWindowController {
    init(
        model: StayPaneModel,
        floatingTimerPreferences: FloatingTimerPreferenceModel,
        launchAtLoginModel: LaunchAtLoginModel
    ) {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 390, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "StayPane"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: StayPaneMenuView(
                model: model,
                floatingTimerPreferences: floatingTimerPreferences,
                launchAtLoginModel: launchAtLoginModel
            )
        )
        panel.center()
        super.init(window: panel)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func showPanel() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
