import Foundation
import StayPaneBridgeProtocol
import StayPaneCore
import Testing
@testable import StayPane

@MainActor
@Test func nativeBridgeHandshakePublishesChromeTabsAndStartsEnforcement() throws {
    let socketURL = temporaryBridgeSocketURL()
    let controller = try NativeBridgeController(socketURL: socketURL)
    let client = try LocalBridgeClient(socketURL: socketURL)
    let profileIdentifier = "profile-test"

    try client.send(
        .hello(
            extensionIdentifier: StayPaneBridgeConstants.extensionIdentifier,
            profileIdentifier: profileIdentifier
        )
    )
    try controller.poll()

    #expect(
        try client.readNextMessage()
            == .helloAcknowledged(profileIdentifier: profileIdentifier)
    )
    #expect(
        try client.readNextMessage()
            == .requestTabs(profileIdentifier: profileIdentifier)
    )

    try client.send(
        .tabsSnapshot(
            profileIdentifier: profileIdentifier,
            tabs: [
                BridgeTabSnapshot(
                    tabIdentifier: 12,
                    windowIdentifier: 4,
                    title: "Swift Documentation",
                    url: "https://www.swift.org/documentation/",
                    faviconDataURL: nil,
                    isActive: true,
                    isIncognito: false
                ),
                BridgeTabSnapshot(
                    tabIdentifier: 13,
                    windowIdentifier: 4,
                    title: "Private",
                    url: "https://example.com/",
                    faviconDataURL: nil,
                    isActive: false,
                    isIncognito: true
                ),
                BridgeTabSnapshot(
                    tabIdentifier: 14,
                    windowIdentifier: 4,
                    title: "Chrome settings",
                    url: "chrome://settings/",
                    faviconDataURL: nil,
                    isActive: false,
                    isIncognito: false
                ),
                BridgeTabSnapshot(
                    tabIdentifier: 15,
                    windowIdentifier: 4,
                    title: "Local file",
                    url: "file:///tmp/notes.txt",
                    faviconDataURL: nil,
                    isActive: false,
                    isIncognito: false
                )
            ]
        )
    )
    try controller.poll()

    let chrome = ApplicationTarget(
        displayName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome"
    )
    let target = try #require(controller.tabTargets(for: chrome).first)
    #expect(controller.isConnected)
    #expect(controller.tabTargets(for: chrome).count == 1)
    #expect(target.title == "Swift Documentation")
    #expect(target.url.host == "www.swift.org")

    try client.send(
        .tabsSnapshot(
            profileIdentifier: profileIdentifier,
            tabs: [
                BridgeTabSnapshot(
                    tabIdentifier: 12,
                    windowIdentifier: 4,
                    title: "Temporarily outside the scope",
                    url: "chrome://settings/",
                    faviconDataURL: nil,
                    isActive: true,
                    isIncognito: false
                )
            ]
        )
    )
    try controller.poll()
    #expect(controller.tabTargets(for: chrome).isEmpty)
    try controller.preflight(targets: enforcementTargets([target]))
    #expect(
        try controller.start(allowing: enforcementTargets([target]))
            == .awaitingConfirmation
    )
    #expect(
        try client.readNextMessage()
            == .beginEnforcement(
                profileIdentifier: profileIdentifier,
                targets: [
                    BridgeEnforcementTarget(
                        tabIdentifier: 12,
                        windowIdentifier: 4,
                        navigationScope: .currentWebsite(
                            initialURL: "https://www.swift.org/documentation/"
                        )
                    )
                ]
            )
    )
    try client.send(
        .enforcementStarted(
            profileIdentifier: profileIdentifier,
            tabIdentifiers: [12]
        )
    )
    try controller.poll()
    #expect(
        try controller.start(allowing: enforcementTargets([target])) == .active
    )

    var blockedNavigationCount = 0
    controller.onBlockedNavigation = {
        blockedNavigationCount += 1
    }
    try client.send(
        .blockedNavigation(
            profileIdentifier: profileIdentifier,
            tabIdentifier: 12
        )
    )
    try controller.poll()
    #expect(blockedNavigationCount == 1)

    controller.stop()
    #expect(
        try client.readNextMessage()
            == .endEnforcement(profileIdentifier: profileIdentifier)
    )
}

@MainActor
@Test func nativeBridgeAtomicallyStartsMixedScopesAndShrinksOnClosure() throws {
    let socketURL = temporaryBridgeSocketURL()
    let controller = try NativeBridgeController(socketURL: socketURL)
    let client = try LocalBridgeClient(socketURL: socketURL)
    let profileIdentifier = "profile-multiple"
    try client.send(
        .hello(
            extensionIdentifier: StayPaneBridgeConstants.extensionIdentifier,
            profileIdentifier: profileIdentifier
        )
    )
    try controller.poll()
    _ = try client.readNextMessage()
    _ = try client.readNextMessage()
    try client.send(
        .tabsSnapshot(
            profileIdentifier: profileIdentifier,
            tabs: [
                BridgeTabSnapshot(
                    tabIdentifier: 31,
                    windowIdentifier: 7,
                    title: "Project",
                    url: "https://work.example/project",
                    faviconDataURL: nil,
                    isActive: true,
                    isIncognito: false
                ),
                BridgeTabSnapshot(
                    tabIdentifier: 32,
                    windowIdentifier: 8,
                    title: "Reference",
                    url: "https://docs.example/reference?v=1#heading",
                    faviconDataURL: nil,
                    isActive: false,
                    isIncognito: false
                )
            ]
        )
    )
    try controller.poll()
    let chrome = ApplicationTarget(
        displayName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome"
    )
    let targets = controller.tabTargets(for: chrome)
    let website = try #require(targets.first(where: {
        $0.tabIdentifier.rawValue == 31
    }))
    let exactSnapshot = try #require(targets.first(where: {
        $0.tabIdentifier.rawValue == 32
    }))
    let exactPage = BrowserTabTarget(
        profileIdentifier: exactSnapshot.profileIdentifier,
        tabIdentifier: exactSnapshot.tabIdentifier,
        windowIdentifier: exactSnapshot.windowIdentifier,
        title: exactSnapshot.title,
        url: exactSnapshot.url,
        faviconPNGData: exactSnapshot.faviconPNGData,
        application: exactSnapshot.application,
        navigationScope: .exactPage
    )

    try controller.preflight(targets: enforcementTargets([website, exactPage]))
    #expect(
        try controller.start(allowing: enforcementTargets([website, exactPage]))
            == .awaitingConfirmation
    )
    #expect(
        try client.readNextMessage()
            == .beginEnforcement(
                profileIdentifier: profileIdentifier,
                targets: [
                    BridgeEnforcementTarget(
                        tabIdentifier: 31,
                        windowIdentifier: 7,
                        navigationScope: .currentWebsite(
                            initialURL: "https://work.example/project"
                        )
                    ),
                    BridgeEnforcementTarget(
                        tabIdentifier: 32,
                        windowIdentifier: 8,
                        navigationScope: .exactPage(
                            initialURL: "https://docs.example/reference?v=1#heading"
                        )
                    )
                ]
            )
    )
    try client.send(
        .enforcementStarted(
            profileIdentifier: profileIdentifier,
            tabIdentifiers: [31, 32]
        )
    )
    try controller.poll()
    #expect(
        try controller.start(allowing: enforcementTargets([website, exactPage]))
            == .active
    )

    var closedTarget: TargetIdentifier?
    controller.onTabTargetClosed = { closedTarget = $0 }
    try client.send(
        .tabTargetClosed(
            profileIdentifier: profileIdentifier,
            tabIdentifier: 31
        )
    )
    try controller.poll()
    #expect(closedTarget == website.targetIdentifier)
    try controller.refresh()

    controller.stop()
    #expect(
        try client.readNextMessage()
            == .endEnforcement(profileIdentifier: profileIdentifier)
    )
}

@MainActor
@Test func nativeBridgeStartsBroadWindowAndPreciseTabTargetsAtomically() throws {
    let socketURL = temporaryBridgeSocketURL()
    let controller = try NativeBridgeController(socketURL: socketURL)
    let client = try LocalBridgeClient(socketURL: socketURL)
    let profileIdentifier = "profile-broad-window"
    try client.send(
        .hello(
            extensionIdentifier: StayPaneBridgeConstants.extensionIdentifier,
            profileIdentifier: profileIdentifier
        )
    )
    try controller.poll()
    _ = try client.readNextMessage()
    _ = try client.readNextMessage()
    try client.send(
        .tabsSnapshot(
            profileIdentifier: profileIdentifier,
            tabs: [
                BridgeTabSnapshot(
                    tabIdentifier: 31,
                    windowIdentifier: 7,
                    title: "Broad work window",
                    url: "chrome://settings/",
                    faviconDataURL: nil,
                    windowBounds: BridgeWindowBounds(
                        left: 120,
                        top: 80,
                        width: 1_200,
                        height: 800
                    ),
                    isActive: true,
                    isIncognito: false
                ),
                BridgeTabSnapshot(
                    tabIdentifier: 32,
                    windowIdentifier: 8,
                    title: "Reference",
                    url: "https://docs.example/reference?v=1",
                    faviconDataURL: nil,
                    isActive: false,
                    isIncognito: false
                )
            ]
        )
    )
    try controller.poll()
    let chrome = ApplicationTarget(
        displayName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome"
    )
    let window = try #require(
        controller.windowTargets(for: chrome).first(where: {
            $0.windowIdentifier.rawValue == 7
        })
    )
    #expect(window.title == "Broad work window")
    #expect(
        window.frame == BrowserWindowFrame(
            x: 120,
            y: 80,
            width: 1_200,
            height: 800
        )
    )
    let tab = try #require(controller.tabTargets(for: chrome).first)
    let browserTargets: [BrowserEnforcementTarget] = [
        .window(window),
        .tab(tab),
    ]

    try controller.preflight(targets: browserTargets)
    #expect(
        try controller.start(allowing: browserTargets)
            == .awaitingConfirmation
    )
    #expect(
        try client.readNextMessage()
            == .beginEnforcement(
                profileIdentifier: profileIdentifier,
                targets: [
                    .window(windowIdentifier: 7),
                    BridgeEnforcementTarget(
                        tabIdentifier: 32,
                        windowIdentifier: 8,
                        navigationScope: .currentWebsite(
                            initialURL: "https://docs.example/reference?v=1"
                        )
                    )
                ]
            )
    )
    try client.send(
        .enforcementStarted(
            profileIdentifier: profileIdentifier,
            windowIdentifiers: [7],
            tabIdentifiers: [32]
        )
    )
    try controller.poll()
    #expect(try controller.start(allowing: browserTargets) == .active)

    var closedWindowTarget: TargetIdentifier?
    controller.onBrowserWindowTargetClosed = { closedWindowTarget = $0 }
    try client.send(
        .browserWindowTargetClosed(
            profileIdentifier: profileIdentifier,
            windowIdentifier: 7
        )
    )
    try controller.poll()
    #expect(closedWindowTarget == window.targetIdentifier)
    try controller.refresh()
}

@MainActor
@Test func disconnectedBridgeRefusesBrowserPreflight() throws {
    let controller = try NativeBridgeController(
        socketURL: temporaryBridgeSocketURL()
    )
    let target = BrowserTabTarget(
        profileIdentifier: BrowserProfileIdentifier(rawValue: "missing"),
        tabIdentifier: BrowserTabIdentifier(rawValue: 1),
        windowIdentifier: BrowserWindowIdentifier(rawValue: 1),
        title: "Missing",
        url: try #require(URL(string: "https://example.com")),
        faviconPNGData: nil,
        application: ApplicationTarget(
            displayName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome"
        )
    )

    #expect(throws: NativeBridgeError.disconnected) {
        try controller.preflight(targets: enforcementTargets([target]))
    }
}

@MainActor
@Test func recoveryWaitsForChromeToReconnectAndConfirmTheSavedTab() throws {
    let currentTime = Date(timeIntervalSince1970: 1_000)
    let socketURL = temporaryBridgeSocketURL()
    let controller = try NativeBridgeController(
        socketURL: socketURL,
        now: { currentTime }
    )
    let target = try savedBrowserTarget(profileIdentifier: "profile-late")

    #expect(
        try controller.resume(allowing: enforcementTargets([target]))
            == .awaitingAvailability
    )
    let client = try LocalBridgeClient(socketURL: socketURL)
    try client.send(
        .hello(
            extensionIdentifier: StayPaneBridgeConstants.extensionIdentifier,
            profileIdentifier: "profile-late"
        )
    )
    #expect(
        try controller.resume(allowing: enforcementTargets([target]))
            == .awaitingAvailability
    )
    _ = try client.readNextMessage()
    _ = try client.readNextMessage()
    try client.send(
        .tabsSnapshot(
            profileIdentifier: "profile-late",
            tabs: [
                BridgeTabSnapshot(
                    tabIdentifier: 1,
                    windowIdentifier: 1,
                    title: "Saved tab",
                    url: "https://example.com",
                    faviconDataURL: nil,
                    isActive: true,
                    isIncognito: false
                )
            ]
        )
    )
    #expect(
        try controller.resume(allowing: enforcementTargets([target]))
            == .awaitingConfirmation
    )
    _ = try client.readNextMessage()
    try client.send(
        .enforcementStarted(
            profileIdentifier: "profile-late",
            tabIdentifiers: [1]
        )
    )
    try controller.poll()
    #expect(
        try controller.resume(allowing: enforcementTargets([target])) == .active
    )
}

@MainActor
@Test func recoveryResumesRemainingTabsAfterASelectedTabWasClosed() throws {
    let socketURL = temporaryBridgeSocketURL()
    let controller = try NativeBridgeController(socketURL: socketURL)
    let client = try LocalBridgeClient(socketURL: socketURL)
    let profileIdentifier = "profile-partial-recovery"
    let remaining = try savedBrowserTarget(
        profileIdentifier: profileIdentifier,
        tabIdentifier: 1,
        windowIdentifier: 7
    )
    let closed = try savedBrowserTarget(
        profileIdentifier: profileIdentifier,
        tabIdentifier: 2,
        windowIdentifier: 8
    )

    try client.send(
        .hello(
            extensionIdentifier: StayPaneBridgeConstants.extensionIdentifier,
            profileIdentifier: profileIdentifier
        )
    )
    try controller.poll()
    _ = try client.readNextMessage()
    _ = try client.readNextMessage()
    try client.send(
        .tabsSnapshot(
            profileIdentifier: profileIdentifier,
            tabs: [
                BridgeTabSnapshot(
                    tabIdentifier: 1,
                    windowIdentifier: 12,
                    title: "Remaining tab",
                    url: "https://example.com",
                    faviconDataURL: nil,
                    isActive: true,
                    isIncognito: false
                )
            ]
        )
    )

    let result = try controller.resume(
        allowing: enforcementTargets([remaining, closed])
    )
    try #require(result == .awaitingConfirmation)
    #expect(
        try client.readNextMessage()
            == .beginEnforcement(
                profileIdentifier: profileIdentifier,
                targets: [
                    BridgeEnforcementTarget(
                        tabIdentifier: 1,
                        windowIdentifier: 12,
                        navigationScope: .currentWebsite(
                            initialURL: "https://example.com"
                        )
                    )
                ]
            )
    )
    try client.send(
        .enforcementStarted(
            profileIdentifier: profileIdentifier,
            tabIdentifiers: [1]
        )
    )
    try controller.poll()

    #expect(
        try controller.resume(
            allowing: enforcementTargets([remaining, closed])
        ) == .active
    )
}

@MainActor
@Test func recoveryFailsOpenAfterTheChromeAvailabilityDeadline() throws {
    var currentTime = Date(timeIntervalSince1970: 1_000)
    let controller = try NativeBridgeController(
        socketURL: temporaryBridgeSocketURL(),
        now: { currentTime }
    )
    let target = try savedBrowserTarget(profileIdentifier: "profile-missing")

    #expect(
        try controller.resume(allowing: enforcementTargets([target]))
            == .awaitingAvailability
    )
    currentTime = currentTime.addingTimeInterval(5)
    #expect(throws: NativeBridgeError.disconnected) {
        try controller.resume(allowing: enforcementTargets([target]))
    }
}

@MainActor
@Test func extensionStartFailureIsReportedBeforeActivationIsConfirmed() throws {
    let socketURL = temporaryBridgeSocketURL()
    let controller = try NativeBridgeController(socketURL: socketURL)
    let client = try LocalBridgeClient(socketURL: socketURL)
    let profileIdentifier = "profile-start-failure"
    try client.send(
        .hello(
            extensionIdentifier: StayPaneBridgeConstants.extensionIdentifier,
            profileIdentifier: profileIdentifier
        )
    )
    try controller.poll()
    _ = try client.readNextMessage()
    _ = try client.readNextMessage()
    try client.send(
        .tabsSnapshot(
            profileIdentifier: profileIdentifier,
            tabs: [
                BridgeTabSnapshot(
                    tabIdentifier: 22,
                    windowIdentifier: 5,
                    title: "Start failure",
                    url: "https://example.com/failure",
                    faviconDataURL: nil,
                    isActive: true,
                    isIncognito: false
                )
            ]
        )
    )
    try controller.poll()
    let target = try #require(
        controller.tabTargets(
            for: ApplicationTarget(
                displayName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome"
            )
        ).first
    )

    #expect(
        try controller.start(allowing: enforcementTargets([target]))
            == .awaitingConfirmation
    )
    _ = try client.readNextMessage()
    try client.send(
        .enforcementError(
            profileIdentifier: profileIdentifier,
            code: .targetMissing
        )
    )
    try controller.poll()

    #expect(
        throws: NativeBridgeError.extensionReported(.targetMissing)
    ) {
        try controller.start(allowing: enforcementTargets([target]))
    }
}

@MainActor
@Test func ticketEightAcceptsOnlyOneChromeProfileConnection() throws {
    let socketURL = temporaryBridgeSocketURL()
    let controller = try NativeBridgeController(socketURL: socketURL)
    let firstClient = try LocalBridgeClient(socketURL: socketURL)
    try firstClient.send(
        .hello(
            extensionIdentifier: StayPaneBridgeConstants.extensionIdentifier,
            profileIdentifier: "profile-first"
        )
    )
    try controller.poll()
    _ = try firstClient.readNextMessage()
    _ = try firstClient.readNextMessage()

    let secondClient = try LocalBridgeClient(socketURL: socketURL)
    try secondClient.send(
        .hello(
            extensionIdentifier: StayPaneBridgeConstants.extensionIdentifier,
            profileIdentifier: "profile-second"
        )
    )
    try controller.poll()

    #expect(controller.isConnected)
    #expect(try secondClient.readNextMessage() == nil)
}

@MainActor
@Test func activeBridgeReportsDisconnectAsEnforcementLoss() throws {
    let socketURL = temporaryBridgeSocketURL()
    let controller = try NativeBridgeController(socketURL: socketURL)
    var client: LocalBridgeClient? = try LocalBridgeClient(socketURL: socketURL)
    let profileIdentifier = "profile-loss"

    try client?.send(
        .hello(
            extensionIdentifier: StayPaneBridgeConstants.extensionIdentifier,
            profileIdentifier: profileIdentifier
        )
    )
    try controller.poll()
    _ = try client?.readNextMessage()
    _ = try client?.readNextMessage()
    try client?.send(
        .tabsSnapshot(
            profileIdentifier: profileIdentifier,
            tabs: [
                BridgeTabSnapshot(
                    tabIdentifier: 8,
                    windowIdentifier: 3,
                    title: "Allowed",
                    url: "https://example.com/allowed",
                    faviconDataURL: nil,
                    isActive: true,
                    isIncognito: false
                )
            ]
        )
    )
    try controller.poll()
    let chrome = ApplicationTarget(
        displayName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome"
    )
    let target = try #require(controller.tabTargets(for: chrome).first)
    #expect(
        try controller.start(allowing: enforcementTargets([target]))
            == .awaitingConfirmation
    )
    _ = try client?.readNextMessage()
    try client?.send(
        .enforcementStarted(
            profileIdentifier: profileIdentifier,
            tabIdentifiers: [8]
        )
    )
    try controller.poll()
    #expect(
        try controller.start(allowing: enforcementTargets([target])) == .active
    )

    client = nil
    try controller.poll()

    #expect(throws: NativeBridgeError.disconnected) {
        try controller.refresh()
    }
}

private func temporaryBridgeSocketURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("sp-\(UUID().uuidString)")
        .appendingPathComponent("bridge.sock")
}

private func savedBrowserTarget(
    profileIdentifier: String,
    tabIdentifier: Int = 1,
    windowIdentifier: Int = 1
) throws -> BrowserTabTarget {
    BrowserTabTarget(
        profileIdentifier: BrowserProfileIdentifier(
            rawValue: profileIdentifier
        ),
        tabIdentifier: BrowserTabIdentifier(rawValue: tabIdentifier),
        windowIdentifier: BrowserWindowIdentifier(rawValue: windowIdentifier),
        title: "Saved tab",
        url: try #require(URL(string: "https://example.com")),
        faviconPNGData: nil,
        application: ApplicationTarget(
            displayName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome"
        )
    )
}

private func enforcementTargets(
    _ tabs: [BrowserTabTarget]
) -> [BrowserEnforcementTarget] {
    tabs.map(BrowserEnforcementTarget.tab)
}
