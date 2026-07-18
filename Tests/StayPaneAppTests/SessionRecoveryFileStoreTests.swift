import Foundation
import StayPaneCore
import Testing
@testable import StayPane

@MainActor
@Test func sessionRecoveryFileStoreRoundTripsAndClearsActiveState() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("StayPaneRecoveryTests")
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = FileSessionRecoveryStore(
        fileURL: directory.appendingPathComponent("session.json")
    )
    let application = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor",
        processIdentifier: 42,
        applicationURL: URL(fileURLWithPath: "/Applications/Editor.app")
    )
    let window = WindowTarget(
        id: WindowIdentifier(
            rawValue: UUID(
                uuidString: "00000000-0000-0000-0000-000000000606"
            )!
        ),
        title: "Draft",
        application: application
    )
    let snapshot = SessionRecoverySnapshot(
        plan: SessionPlan(
            id: UUID(
                uuidString: "00000000-0000-0000-0000-000000000600"
            )!,
            duration: SessionDuration(seconds: 600)!,
            targets: [.window(window)],
            preparedAt: Date(timeIntervalSince1970: 10_000)
        ),
        startedAt: Date(timeIntervalSince1970: 10_003),
        endsAt: Date(timeIntervalSince1970: 10_603),
        phase: .resetPending(
            requestedAt: Date(timeIntervalSince1970: 10_100),
            confirmationAvailableAt: Date(timeIntervalSince1970: 10_130)
        )
    )

    try store.save(snapshot)

    #expect(try store.load() == snapshot)

    try store.clear()

    #expect(try store.load() == nil)
}
