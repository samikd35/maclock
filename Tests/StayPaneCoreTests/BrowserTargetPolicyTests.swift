import Foundation
import Testing
@testable import StayPaneCore

@Test func chromeApplicationSelectionOwnsItsEntireBrowserHierarchy() {
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
    let window = BrowserWindowTarget(
        profileIdentifier: BrowserProfileIdentifier(rawValue: "profile-one"),
        windowIdentifier: BrowserWindowIdentifier(rawValue: 7),
        application: chrome
    )
    var policy = TargetSelectionPolicy()

    let selectedWindow = policy.select(.browserWindow(window))
    #expect(selectedWindow)
    #expect(policy.targets == [.browserWindow(window)])
    let rejectedChildTab = policy.select(.browserTab(firstTab))
    #expect(!rejectedChildTab)
    #expect(policy.targets == [.browserWindow(window)])

    policy.deselect(window.targetIdentifier)
    let selectedFirstTab = policy.select(.browserTab(firstTab))
    #expect(selectedFirstTab)
    #expect(policy.targets == [.browserTab(firstTab)])
    let selectedSecondTab = policy.select(.browserTab(secondTab))
    #expect(selectedSecondTab)
    #expect(policy.targets == [.browserTab(firstTab), .browserTab(secondTab)])

    let selectedApplication = policy.select(.application(chrome))
    #expect(selectedApplication)
    #expect(policy.targets == [.application(chrome)])
    let rejectedWindow = policy.select(.browserWindow(window))
    let rejectedTab = policy.select(.browserTab(firstTab))
    #expect(!rejectedWindow)
    #expect(!rejectedTab)
    #expect(policy.targets == [.application(chrome)])

    policy.deselect(TargetIdentifier.application(bundleIdentifier: chrome.bundleIdentifier))
    let selectedWindowAfterApplication = policy.select(.browserWindow(window))
    #expect(selectedWindowAfterApplication)
    #expect(policy.targets == [.browserWindow(window)])

    let selectedApplicationOverWindow = policy.select(.application(chrome))
    #expect(selectedApplicationOverWindow)
    #expect(policy.targets == [.application(chrome)])

    policy.deselect(TargetIdentifier.application(bundleIdentifier: chrome.bundleIdentifier))
    let selectedTabAfterApplication = policy.select(.browserTab(firstTab))
    #expect(selectedTabAfterApplication)
    #expect(policy.targets == [.browserTab(firstTab)])
}

@Test func chromeWindowSelectionOwnsOnlyTabsInsideThatWindow() {
    let chrome = ApplicationTarget(
        displayName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome"
    )
    let firstWindow = BrowserWindowTarget(
        profileIdentifier: BrowserProfileIdentifier(rawValue: "profile-one"),
        windowIdentifier: BrowserWindowIdentifier(rawValue: 7),
        application: chrome
    )
    let secondWindow = BrowserWindowTarget(
        profileIdentifier: BrowserProfileIdentifier(rawValue: "profile-one"),
        windowIdentifier: BrowserWindowIdentifier(rawValue: 8),
        application: chrome
    )
    let childTab = makeTab(
        id: 11,
        windowID: 7,
        application: chrome
    )
    let siblingWindowTab = makeTab(
        id: 12,
        windowID: 8,
        application: chrome
    )
    var policy = TargetSelectionPolicy(
        targets: [.browserTab(childTab), .browserTab(siblingWindowTab)]
    )

    let selectedFirstWindow = policy.select(.browserWindow(firstWindow))
    #expect(selectedFirstWindow)
    #expect(
        policy.targets == [
            .browserWindow(firstWindow),
            .browserTab(siblingWindowTab),
        ]
    )
    let rejectedChildTab = policy.select(.browserTab(childTab))
    #expect(!rejectedChildTab)
    let selectedSecondWindow = policy.select(.browserWindow(secondWindow))
    #expect(selectedSecondWindow)
    #expect(
        policy.targets == [
            .browserWindow(firstWindow),
            .browserWindow(secondWindow),
        ]
    )

    policy.deselect(firstWindow.targetIdentifier)
    let selectedChildTab = policy.select(.browserTab(childTab))
    #expect(selectedChildTab)
    #expect(
        policy.targets == [
            .browserWindow(secondWindow),
            .browserTab(childTab),
        ]
    )
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

private func makeTab(
    id: Int,
    windowID: Int,
    application: ApplicationTarget
) -> BrowserTabTarget {
    BrowserTabTarget(
        profileIdentifier: BrowserProfileIdentifier(rawValue: "profile-one"),
        tabIdentifier: BrowserTabIdentifier(rawValue: id),
        windowIdentifier: BrowserWindowIdentifier(rawValue: windowID),
        title: "Tab \(id)",
        url: URL(string: "https://work.example/\(id)")!,
        faviconPNGData: nil,
        application: application
    )
}
