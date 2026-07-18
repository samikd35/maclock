import Foundation
import StayPaneCore

@MainActor
final class FileSessionRecoveryStore: SessionRecoveryPersisting {
    private enum StoredRecovery: Codable {
        case active(SessionRecoverySnapshot)
        case interrupted
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
        try file.save(.active(snapshot))
    }

    func markInterrupted() throws {
        try file.save(.interrupted)
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
