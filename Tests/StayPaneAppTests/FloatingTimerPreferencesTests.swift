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
                scale: 0.5,
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
                scale: 0.5,
                origin: CGPoint(x: 320, y: 180)
            )
    )
}

@MainActor
@Test func floatingTimerScaleClampsAndPersistsAcrossRelaunch() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = FloatingTimerPreferenceModel(defaults: defaults)

    preferences.setScale(2)
    #expect(preferences.value.scale == 1)
    #expect(!preferences.canIncreaseSize)

    let largeReload = FloatingTimerPreferenceModel(defaults: defaults)
    #expect(largeReload.value.scale == 1)

    largeReload.setScale(-1)
    #expect(largeReload.value.scale == 0)
    #expect(!largeReload.canDecreaseSize)

    let smallReload = FloatingTimerPreferenceModel(defaults: defaults)
    #expect(smallReload.value.scale == 0)
}

@MainActor
@Test func legacyFloatingTimerSizeMigratesToContinuousScale() {
    let (defaults, suiteName) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("large", forKey: "floatingTimerSize")

    let preferences = FloatingTimerPreferenceModel(defaults: defaults)

    #expect(preferences.value.scale == 1)
    #expect(defaults.double(forKey: "floatingTimerScale") == 1)
}

@Test func floatingTimerSizesChangeExpandedAndCollapsedGeometry() {
    let small = FloatingTimerLayoutMetrics.resolve(
        scale: 0,
        isCollapsed: false
    )
    let medium = FloatingTimerLayoutMetrics.resolve(
        scale: 0.5,
        isCollapsed: false
    )
    let large = FloatingTimerLayoutMetrics.resolve(
        scale: 1,
        isCollapsed: false
    )
    let collapsed = FloatingTimerLayoutMetrics.resolve(
        scale: 0.5,
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
        styleMask: [.borderless, .nonactivatingPanel, .resizable],
        backing: .buffered,
        defer: false
    )

    #expect(panel.canBecomeKey)
    #expect(panel.styleMask.contains(.resizable))
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
    for scale in [0.0, 0.5, 1.0] {
        let metrics = FloatingTimerLayoutMetrics.resolve(
            scale: scale,
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

@Test func floatingTimerResizeGeometryReturnsCanonicalProportionalSizes() {
    let current = FloatingTimerLayoutMetrics.resolve(
        scale: 0.5,
        isCollapsed: false
    ).contentSize
    let proposed = CGSize(width: 520, height: current.height)

    let scale = FloatingTimerResizeGeometry.scale(
        forProposedSize: proposed,
        currentSize: current,
        currentScale: 0.5,
        isCollapsed: false
    )
    let canonical = FloatingTimerLayoutMetrics.resolve(
        scale: scale,
        isCollapsed: false
    ).contentSize

    #expect(scale == 1)
    #expect(canonical == CGSize(width: 520, height: 116))
}

private func makeDefaults() -> (UserDefaults, String) {
    let suiteName = "FloatingTimerPreferencesTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}
