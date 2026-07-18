import Foundation
import StayPaneBridgeProtocol
import StayPaneCore
import Testing
@testable import StayPane

@MainActor
@Test func bridgeHandshakePublishesChromeTabsAndStartsEnforcement() throws {
    let socketURL = temporaryBridgeSocketURL()
    let controller = try BrowserBridgeController(socketURL: socketURL)
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
    try controller.start(allowing: [target])
    #expect(
        try client.readNextMessage()
            == .beginEnforcement(
                profileIdentifier: profileIdentifier,
                tabIdentifier: 12,
                windowIdentifier: 4
            )
    )

    controller.stop()
    #expect(
        try client.readNextMessage()
            == .endEnforcement(profileIdentifier: profileIdentifier)
    )
}

@MainActor
@Test func disconnectedBridgeRefusesBrowserPreflight() throws {
    let controller = try BrowserBridgeController(
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

    #expect(throws: BrowserBridgeError.disconnected) {
        try controller.preflight(targets: [target])
    }
}

@MainActor
@Test func activeBridgeReportsDisconnectAsEnforcementLoss() throws {
    let socketURL = temporaryBridgeSocketURL()
    let controller = try BrowserBridgeController(socketURL: socketURL)
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
    try controller.start(allowing: [target])
    _ = try client?.readNextMessage()

    client = nil
    try controller.poll()

    #expect(throws: BrowserBridgeError.disconnected) {
        try controller.refresh()
    }
}

private func temporaryBridgeSocketURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("sp-\(UUID().uuidString)")
        .appendingPathComponent("bridge.sock")
}
