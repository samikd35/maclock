import Foundation
import StayPaneCore
import Testing
@testable import StayPane

@MainActor
@Test func windowEnforcementFileStoreRoundTripsAndClearsPlatformState() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("StayPaneWindowEnforcementTests")
        .appendingPathComponent(UUID().uuidString)
    let fileURL = directory.appendingPathComponent("window-enforcement.json")
    let store = FileWindowEnforcementStore(fileURL: fileURL)
    let allowedReference = ExactWindowReference(
        windowIdentifier: WindowIdentifier(),
        bundleIdentifier: "com.example.editor",
        processIdentifier: 901,
        accessibilityIdentifier: "allowed-window-901"
    )
    let restorationReference = ExactWindowReference(
        windowIdentifier: WindowIdentifier(),
        bundleIdentifier: "com.example.reference",
        processIdentifier: 902,
        accessibilityIdentifier: "changed-window-902"
    )
    let snapshot = WindowEnforcementSnapshot(
        allowedWindowReferences: [allowedReference],
        restorationReferences: [restorationReference]
    )

    try store.save(snapshot)

    #expect(try store.load() == snapshot)
    try store.clear()
    #expect(try store.load() == nil)
    try? FileManager.default.removeItem(at: directory)
}
