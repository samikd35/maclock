import Foundation
import Testing
@testable import StayPaneBridgeProtocol

@Test func registrationWritesARestrictedChromeNativeHostManifest() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("StayPaneNativeHostInstallerTests")
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    let executableURL = directory.appendingPathComponent("StayPaneBridge")
    try Data("bridge".utf8).write(to: executableURL)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: executableURL.path
    )
    let manifestDirectory = directory.appendingPathComponent("NativeMessagingHosts")
    let installer = NativeMessagingHostInstaller(
        manifestDirectoryURL: manifestDirectory
    )

    let manifestURL = try installer.install(
        hostExecutableURL: executableURL
    )

    #expect(
        manifestURL
            == manifestDirectory.appendingPathComponent(
                "com.staypane.native_bridge.json"
            )
    )
    let manifest = try JSONDecoder().decode(
        NativeMessagingHostManifest.self,
        from: Data(contentsOf: manifestURL)
    )
    #expect(manifest.name == "com.staypane.native_bridge")
    #expect(manifest.path == executableURL.path)
    #expect(manifest.type == "stdio")
    #expect(
        manifest.allowedOrigins
            == ["chrome-extension://hoofhoedlagpoclhkgnkmejaihaapoke/"]
    )
    #expect(
        installer.registrationStatus(hostExecutableURL: executableURL)
            == .installed
    )
}

@Test func registrationStatusDistinguishesAStaleExecutablePath() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("StayPaneStaleNativeHostTests")
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let manifestDirectory = directory.appendingPathComponent(
        "NativeMessagingHosts"
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    let installer = NativeMessagingHostInstaller(
        manifestDirectoryURL: manifestDirectory
    )
    let staleExecutable = directory.appendingPathComponent("OldStayPaneBridge")
    let installedExecutable = directory.appendingPathComponent("StayPaneBridge")
    for executableURL in [staleExecutable, installedExecutable] {
        try Data("bridge".utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executableURL.path
        )
    }

    try installer.install(hostExecutableURL: staleExecutable)

    #expect(
        installer.registrationStatus(
            hostExecutableURL: installedExecutable
        ) == .pointsElsewhere(staleExecutable.standardizedFileURL)
    )
}

@Test func registrationRejectsAMissingBridgeExecutable() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("StayPaneMissingNativeHostTests")
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let installer = NativeMessagingHostInstaller(
        manifestDirectoryURL: directory.appendingPathComponent(
            "NativeMessagingHosts"
        )
    )

    #expect(throws: NativeMessagingHostInstallerError.hostExecutableMissing) {
        try installer.install(
            hostExecutableURL: directory.appendingPathComponent("missing")
        )
    }
}
