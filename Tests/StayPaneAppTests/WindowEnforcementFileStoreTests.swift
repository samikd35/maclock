import Foundation
import StayPaneCore
import Testing
@testable import StayPane

@Test func exactWindowReferenceRejectsAmbiguousPersistedIdentity() throws {
    let reference = ExactWindowReference(
        windowIdentifier: WindowIdentifier(),
        bundleIdentifier: "com.example.editor",
        processIdentifier: 901,
        accessibilityIdentifier: "window-901"
    )
    let encoded = try JSONEncoder().encode(reference)
    var object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object["coreGraphicsWindowNumber"] = 901
    let ambiguous = try JSONSerialization.data(withJSONObject: object)
    object.removeValue(forKey: "accessibilityIdentifier")
    object.removeValue(forKey: "coreGraphicsWindowNumber")
    let missing = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ExactWindowReference.self, from: ambiguous)
    }
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ExactWindowReference.self, from: missing)
    }
}

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
        coreGraphicsWindowNumber: 902
    )
    let pendingReference = ExactWindowReference(
        windowIdentifier: WindowIdentifier(),
        bundleIdentifier: "com.example.pending",
        processIdentifier: 903,
        coreGraphicsWindowNumber: 903
    )
    let snapshot = WindowEnforcementSnapshot(
        allowedWindowReferences: [allowedReference],
        restorationReferences: [restorationReference],
        pendingMutationReference: pendingReference
    )

    try store.save(snapshot)

    #expect(try store.load() == snapshot)
    try store.clear()
    #expect(try store.load() == nil)
    try? FileManager.default.removeItem(at: directory)
}

@Test func legacyWindowEnforcementSnapshotDefaultsToNoPendingMutation() throws {
    let snapshot = WindowEnforcementSnapshot(
        allowedWindowReferences: [],
        restorationReferences: []
    )
    let encoded = try JSONEncoder().encode(snapshot)
    var object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "pendingMutationReference")
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(
        WindowEnforcementSnapshot.self,
        from: legacyData
    )

    #expect(decoded.pendingMutationReference == nil)
}
