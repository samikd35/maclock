import CoreGraphics
import Foundation
import Testing
@testable import StayPane

@MainActor
@Test func floatingTimerPreferencesDefaultToVisibleAndExpanded() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let preferences = FloatingTimerPreferenceModel(defaults: defaults)

    #expect(
        preferences.value
            == FloatingTimerPreferences(
                isVisible: true,
                isCollapsed: false,
                origin: nil
            )
    )
}

@MainActor
@Test func floatingTimerChoicesAndPositionSurviveRelaunch() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = FloatingTimerPreferenceModel(defaults: defaults)

    preferences.setVisible(false)
    preferences.toggleCollapsed()
    preferences.move(to: CGPoint(x: 320, y: 180))
    let reloaded = FloatingTimerPreferenceModel(defaults: defaults)

    #expect(
        reloaded.value
            == FloatingTimerPreferences(
                isVisible: false,
                isCollapsed: true,
                origin: CGPoint(x: 320, y: 180)
            )
    )
}

private func makeDefaults() -> (UserDefaults, String) {
    let suiteName = "FloatingTimerPreferencesTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}
