import AppKit
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
                size: .medium,
                origin: nil
            )
    )
}

@MainActor
@Test func floatingTimerLayoutSurvivesRelaunchWithoutPersistingAHiddenSession() {
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
                isVisible: true,
                isCollapsed: true,
                size: .medium,
                origin: CGPoint(x: 320, y: 180)
            )
    )
}

@MainActor
@Test func floatingTimerSizeControlsClampAndPersistAcrossRelaunch() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = FloatingTimerPreferenceModel(defaults: defaults)

    preferences.increaseSize()
    preferences.increaseSize()
    #expect(preferences.value.size == .large)
    #expect(!preferences.canIncreaseSize)

    let largeReload = FloatingTimerPreferenceModel(defaults: defaults)
    #expect(largeReload.value.size == .large)

    largeReload.decreaseSize()
    largeReload.decreaseSize()
    largeReload.decreaseSize()
    #expect(largeReload.value.size == .small)
    #expect(!largeReload.canDecreaseSize)

    let smallReload = FloatingTimerPreferenceModel(defaults: defaults)
    #expect(smallReload.value.size == .small)
}

@Test func floatingTimerSizesChangeExpandedAndCollapsedGeometry() {
    let small = FloatingTimerLayoutMetrics.resolve(
        size: .small,
        isCollapsed: false
    )
    let medium = FloatingTimerLayoutMetrics.resolve(
        size: .medium,
        isCollapsed: false
    )
    let large = FloatingTimerLayoutMetrics.resolve(
        size: .large,
        isCollapsed: false
    )
    let collapsed = FloatingTimerLayoutMetrics.resolve(
        size: .medium,
        isCollapsed: true
    )

    #expect(small.contentSize.width < medium.contentSize.width)
    #expect(medium.contentSize.width < large.contentSize.width)
    #expect(small.timeFontSize < medium.timeFontSize)
    #expect(medium.timeFontSize < large.timeFontSize)
    #expect(collapsed.contentSize.width < medium.contentSize.width)
    #expect(collapsed.contentSize.height < medium.contentSize.height)
}

@MainActor
@Test func floatingTimerPositionCanResetToTheSafeDefault() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = FloatingTimerPreferenceModel(defaults: defaults)

    preferences.move(to: CGPoint(x: 320, y: 180))
    preferences.resetPosition()

    #expect(preferences.value.origin == nil)
    #expect(FloatingTimerPreferenceModel(defaults: defaults).value.origin == nil)
}

@MainActor
@Test func floatingTimerPanelSupportsKeyboardControlsAndFullScreenSpaces() {
    let panel = FloatingTimerPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )

    #expect(panel.canBecomeKey)
    #expect(
        FloatingTimerPanel.requiredCollectionBehavior
            .contains(.canJoinAllApplications)
    )
    #expect(
        FloatingTimerPanel.requiredCollectionBehavior
            .contains(.fullScreenAuxiliary)
    )
}

@Test func collapsedTimerFitsTheLongestSupportedCountdownAtEverySize() {
    for size in FloatingTimerSize.allCases {
        let metrics = FloatingTimerLayoutMetrics.resolve(
            size: size,
            isCollapsed: true
        )
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: metrics.timeFontSize,
            weight: .bold
        )
        let countdownWidth = ("24:00:00" as NSString).size(
            withAttributes: [.font: font]
        ).width
        let controlWidth = max(20, metrics.iconFontSize + 8)
        let requiredWidth = countdownWidth
            + (controlWidth * 3)
            + (metrics.spacing * 3)
            + (metrics.horizontalPadding * 2)

        #expect(metrics.contentSize.width >= requiredWidth)
    }
}

private func makeDefaults() -> (UserDefaults, String) {
    let suiteName = "FloatingTimerPreferencesTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}
