import Foundation

@MainActor
protocol WindowRecoveryPersisting: AnyObject {
    func load() throws -> [RecoverableWindowReference]
    func save(_ references: [RecoverableWindowReference]) throws
    func clear() throws
}

@MainActor
final class FileWindowRecoveryStore: WindowRecoveryPersisting {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileURL: URL = FileWindowRecoveryStore.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() throws -> [RecoverableWindowReference] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        return try decoder.decode(
            [RecoverableWindowReference].self,
            from: Data(contentsOf: fileURL)
        )
    }

    func save(_ references: [RecoverableWindowReference]) throws {
        guard !references.isEmpty else {
            try clear()
            return
        }
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(references).write(to: fileURL, options: .atomic)
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
        .appendingPathComponent("changed-windows.json", isDirectory: false)
    }
}

@MainActor
final class NoWindowRecoveryStore: WindowRecoveryPersisting {
    func load() throws -> [RecoverableWindowReference] {
        []
    }

    func save(_ references: [RecoverableWindowReference]) throws {}

    func clear() throws {}
}
