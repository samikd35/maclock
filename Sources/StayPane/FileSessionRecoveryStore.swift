import Foundation
import StayPaneCore

@MainActor
final class FileSessionRecoveryStore: SessionRecoveryPersisting {
    private struct InterruptionMarker: Codable {
        let interruptedAt: Date
        let reason: SessionInterruptionReason
    }

    private enum StoredRecovery: Codable {
        case active(SessionRecoverySnapshot)
        case interrupted(InterruptionMarker)
    }

    private let file: LocalJSONFile<StoredRecovery>

    init(
        fileURL: URL = FileSessionRecoveryStore.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        file = LocalJSONFile(fileURL: fileURL, fileManager: fileManager)
    }

    func load() throws -> SessionRecoverySnapshot? {
        guard let storedRecovery = try file.load() else {
            return nil
        }
        guard case let .active(snapshot) = storedRecovery else {
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: SessionRecoverySnapshot) throws {
        try write(.active(snapshot))
    }

    func markInterrupted(
        at interruptedAt: Date,
        reason: SessionInterruptionReason
    ) throws {
        try write(
            .interrupted(
                InterruptionMarker(
                    interruptedAt: interruptedAt,
                    reason: reason
                )
            )
        )
    }

    private func write(_ storedRecovery: StoredRecovery) throws {
        try file.save(storedRecovery)
    }

    func clear() throws {
        try file.clear()
    }

    private static var defaultFileURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("StayPane", isDirectory: true)
        .appendingPathComponent("active-session.json", isDirectory: false)
    }
}
