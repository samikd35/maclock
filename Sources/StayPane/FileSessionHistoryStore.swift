import Foundation
import StayPaneCore

@MainActor
final class FileSessionHistoryStore: SessionHistoryStoring {
    private static let maximumRecordCount = 100

    private let file: LocalJSONFile<[SessionHistoryRecord]>

    init(
        fileURL: URL = FileSessionHistoryStore.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        file = LocalJSONFile(fileURL: fileURL, fileManager: fileManager)
    }

    func load() throws -> [SessionHistoryRecord] {
        try file.load() ?? []
    }

    func record(_ record: SessionHistoryRecord) throws {
        var records = try load()
        records.append(record)
        try file.save(Array(records.suffix(Self.maximumRecordCount)))
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
        .appendingPathComponent("session-history.json", isDirectory: false)
    }
}
