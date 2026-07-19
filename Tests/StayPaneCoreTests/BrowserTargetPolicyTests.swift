import Foundation
import Testing
@testable import StayPaneCore

@Test func selectingTabsReplacesBroaderChromeTargetsButKeepsEarlierTabs() {
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
    #expect(policy.targets == [.browserTab(firstTab), .browserTab(secondTab)])

    let selectedApplication = policy.select(.application(chrome))
    #expect(selectedApplication)
    #expect(policy.targets == [.application(chrome)])
}

@Test func eachTabPersistsItsIndependentNavigationScope() throws {
    let chrome = ApplicationTarget(
        displayName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome"
    )
    let websiteTab = BrowserTabTarget(
        profileIdentifier: BrowserProfileIdentifier(rawValue: "profile-one"),
        tabIdentifier: BrowserTabIdentifier(rawValue: 41),
        windowIdentifier: BrowserWindowIdentifier(rawValue: 9),
        title: "Project",
        url: URL(string: "https://work.example/project")!,
        faviconPNGData: nil,
        application: chrome,
        navigationScope: .currentWebsite
    )
    let exactPageTab = BrowserTabTarget(
        profileIdentifier: BrowserProfileIdentifier(rawValue: "profile-one"),
        tabIdentifier: BrowserTabIdentifier(rawValue: 42),
        windowIdentifier: BrowserWindowIdentifier(rawValue: 10),
        title: "Reference",
        url: URL(string: "https://docs.example/reference?version=1#heading")!,
        faviconPNGData: nil,
        application: chrome,
        navigationScope: .exactPage
    )

    let decoded = try JSONDecoder().decode(
        [BrowserTabTarget].self,
        from: JSONEncoder().encode([websiteTab, exactPageTab])
    )

    #expect(decoded == [websiteTab, exactPageTab])
}

@Test func individualTabsDefaultToCurrentWebsiteNavigationScope() throws {
    let target = BrowserTabTarget(
        profileIdentifier: BrowserProfileIdentifier(rawValue: "profile-one"),
        tabIdentifier: BrowserTabIdentifier(rawValue: 41),
        windowIdentifier: BrowserWindowIdentifier(rawValue: 9),
        title: "Project plan",
        url: URL(string: "https://work.example/project?view=board")!,
        faviconPNGData: nil,
        application: ApplicationTarget(
            displayName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome"
        )
    )

    #expect(target.navigationScope == .currentWebsite)

    let encoded = try JSONEncoder().encode(target)
    var legacyObject = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    legacyObject.removeValue(forKey: "navigationScope")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)

    #expect(
        try JSONDecoder().decode(BrowserTabTarget.self, from: legacyData)
            .navigationScope == .currentWebsite
    )
}
