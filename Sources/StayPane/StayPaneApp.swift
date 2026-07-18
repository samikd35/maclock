import AppKit
import SwiftUI

@MainActor
final class StayPaneAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: StayPaneModel?

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard let model else {
            return .terminateNow
        }
        return model.handleQuitRequest() ? .terminateNow : .terminateCancel
    }
}

@main
@MainActor
struct StayPaneApp: App {
    @NSApplicationDelegateAdaptor(StayPaneAppDelegate.self) private var appDelegate
    @StateObject private var model: StayPaneModel

    init() {
        let model = StayPaneModel()
        _model = StateObject(wrappedValue: model)
        appDelegate.model = model
    }

    var body: some Scene {
        MenuBarExtra {
            StayPaneMenuView(model: model)
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
