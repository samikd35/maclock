import SwiftUI

@main
@MainActor
struct StayPaneApp: App {
    @StateObject private var model = StayPaneModel()

    var body: some Scene {
        MenuBarExtra {
            StayPaneMenuView(model: model)
        } label: {
            Label(model.menuBarTitle, systemImage: "rectangle.inset.filled.and.person.filled")
        }
        .menuBarExtraStyle(.window)
    }
}
