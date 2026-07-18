import Foundation
import StayPaneCore
import Testing
@testable import StayPane

@MainActor
@Test func windowRecoveryFileStoreRoundTripsAndClearsRestorationState() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("StayPaneWindowRecoveryTests")
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = FileWindowRecoveryStore(
        fileURL: directory.appendingPathComponent("windows.json")
    )
    let reference = RecoverableWindowReference(
        windowIdentifier: WindowIdentifier(
            rawValue: UUID(
                uuidString: "00000000-0000-0000-0000-000000000660"
            )!
        ),
        bundleIdentifier: "com.example.editor",
        processIdentifier: 66,
        accessibilityIdentifier: "editor-draft-66"
    )

    try store.save([reference])

    #expect(try store.load() == [reference])

    try store.clear()

    #expect(try store.load().isEmpty)
}
