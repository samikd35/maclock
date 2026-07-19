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
    let target = try #require(controller.targets(for: chrome).first)
    #expect(controller.isConnected)
    #expect(controller.targets(for: chrome).count == 1)
    #expect(target.title == "Swift Documentation")
    #expect(target.url.host == "www.swift.org")

    try controller.preflight(targets: [target])
    #expect(
        try controller.start(allowing: [target]) == .awaitingConfirmation
    )
    #expect(
        try client.readNextMessage()
            == .beginEnforcement(
                profileIdentifier: profileIdentifier,
                tabIdentifier: 12,
                windowIdentifier: 4,
                navigationScope: .currentWebsite(
                    initialURL: "https://www.swift.org/documentation/"
                )
            )
    )
    try client.send(
        .tabActivationStarted(
            profileIdentifier: profileIdentifier,
            tabIdentifier: 12,
            windowIdentifier: 4
        )
    )
    try controller.poll()
    #expect(try controller.start(allowing: [target]) == .active)

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
        try controller.preflight(targets: [target])
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
        try controller.resume(allowing: [target]) == .awaitingAvailability
    )
    let client = try LocalBridgeClient(socketURL: socketURL)
    try client.send(
        .hello(
            extensionIdentifier: StayPaneBridgeConstants.extensionIdentifier,
            profileIdentifier: "profile-late"
        )
    )
    #expect(
        try controller.resume(allowing: [target]) == .awaitingAvailability
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
        try controller.resume(allowing: [target]) == .awaitingConfirmation
    )
    _ = try client.readNextMessage()
    try client.send(
        .tabActivationStarted(
            profileIdentifier: "profile-late",
            tabIdentifier: 1,
            windowIdentifier: 1
        )
    )
    try controller.poll()
    #expect(try controller.resume(allowing: [target]) == .active)
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
        try controller.resume(allowing: [target]) == .awaitingAvailability
    )
    currentTime = currentTime.addingTimeInterval(5)
    #expect(throws: NativeBridgeError.disconnected) {
        try controller.resume(allowing: [target])
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
        controller.targets(
            for: ApplicationTarget(
                displayName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome"
            )
        ).first
    )

    #expect(
        try controller.start(allowing: [target]) == .awaitingConfirmation
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
        try controller.start(allowing: [target])
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
    let target = try #require(controller.targets(for: chrome).first)
    #expect(
        try controller.start(allowing: [target]) == .awaitingConfirmation
    )
    _ = try client?.readNextMessage()
    try client?.send(
        .tabActivationStarted(
            profileIdentifier: profileIdentifier,
            tabIdentifier: 8,
            windowIdentifier: 3
        )
    )
    try controller.poll()
    #expect(try controller.start(allowing: [target]) == .active)

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
    profileIdentifier: String
) throws -> BrowserTabTarget {
    BrowserTabTarget(
        profileIdentifier: BrowserProfileIdentifier(
            rawValue: profileIdentifier
        ),
        tabIdentifier: BrowserTabIdentifier(rawValue: 1),
        windowIdentifier: BrowserWindowIdentifier(rawValue: 1),
        title: "Saved tab",
        url: try #require(URL(string: "https://example.com")),
        faviconPNGData: nil,
        application: ApplicationTarget(
            displayName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome"
        )
    )
}
