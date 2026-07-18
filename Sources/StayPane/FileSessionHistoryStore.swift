import Foundation
import StayPaneCore

@MainActor
final class FileSessionHistoryStore: SessionHistoryStoring {
    private static let maximumRecordCount = 100

    private let records: BoundedLocalJSONCollection<SessionHistoryRecord>

    init(
        fileURL: URL = FileSessionHistoryStore.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        records = BoundedLocalJSONCollection(
            fileURL: fileURL,
            maximumCount: Self.maximumRecordCount,
            fileManager: fileManager
        )
    }

    func load() throws -> [SessionHistoryRecord] {
        try records.load()
    }

    func record(_ record: SessionHistoryRecord) throws {
        try records.append(record)
    }

    func clear() throws {
        try records.clear()
    }

    private static var defaultFileURL: URL {
        StayPaneStorageLocation.applicationSupportFile(
            named: "session-history.json"
        )
    }
}
