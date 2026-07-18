import Foundation
import StayPaneCore

@MainActor
final class FileSessionRecoveryStore: SessionRecoveryPersisting {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileURL: URL = FileSessionRecoveryStore.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() throws -> SessionRecoverySnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try decoder.decode(
            SessionRecoverySnapshot.self,
            from: Data(contentsOf: fileURL)
        )
    }

    func save(_ snapshot: SessionRecoverySnapshot) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }
        try fileManager.removeItem(at: fileURL)
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
