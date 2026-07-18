import Foundation
import Testing
@testable import StayPaneCore

@Test func selectingOneTabReplacesBroaderChromeTargetsAndEarlierTabs() {
    let chrome = ApplicationTarget(
        displayName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome"
    )
    let firstTab = BrowserTabTarget(
        profileIdentifier: BrowserProfileIdentifier(rawValue: "profile-one"),
        tabIdentifier: BrowserTabIdentifier(rawValue: 11),
        windowIdentifier: BrowserWindowIdentifier(rawValue: 7),
        title: "Project plan",
        url: URL(string: "https://work.example/project")!,
        faviconPNGData: nil,
        application: chrome
    )
    let secondTab = BrowserTabTarget(
        profileIdentifier: BrowserProfileIdentifier(rawValue: "profile-one"),
        tabIdentifier: BrowserTabIdentifier(rawValue: 12),
        windowIdentifier: BrowserWindowIdentifier(rawValue: 7),
        title: "Reference",
        url: URL(string: "https://docs.example/reference")!,
        faviconPNGData: Data([0x89, 0x50, 0x4E, 0x47]),
        application: chrome
    )
    var policy = TargetSelectionPolicy(targets: [.application(chrome)])

    let selectedFirstTab = policy.select(.browserTab(firstTab))
    #expect(selectedFirstTab)
    #expect(policy.targets == [.browserTab(firstTab)])

    let selectedSecondTab = policy.select(.browserTab(secondTab))
    #expect(selectedSecondTab)
    #expect(policy.targets == [.browserTab(secondTab)])

    let selectedApplication = policy.select(.application(chrome))
    #expect(selectedApplication)
    #expect(policy.targets == [.application(chrome)])
}
