import Foundation
import StayPaneCore
import Testing
@testable import StayPane

@MainActor
@Test func sessionHistoryFileStoreRoundTripsAndClearsMinimalRecords() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("StayPaneSessionHistoryTests")
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("history.json")
    let store = FileSessionHistoryStore(fileURL: fileURL)
    let record = SessionHistoryRecord(
        startedAt: Date(timeIntervalSince1970: 40_000),
        plannedDuration: SessionDuration(seconds: 1_800)!,
        actualFocusTime: 1_799,
        result: .completed
    )

    try store.record(record)

    #expect(try store.load() == [record])
    try store.clear()
    #expect(try store.load().isEmpty)
}

@MainActor
@Test func sessionHistoryRetainsOnlyTheLatestOneHundredRecords() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("StayPaneBoundedHistoryTests")
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = FileSessionHistoryStore(
        fileURL: directory.appendingPathComponent("history.json")
    )

    for index in 0..<105 {
        try store.record(
            SessionHistoryRecord(
                startedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                plannedDuration: SessionDuration(seconds: 10)!,
                actualFocusTime: 10,
                result: .completed
            )
        )
    }

    let records = try store.load()
    #expect(records.count == 100)
    #expect(records.first?.startedAt == Date(timeIntervalSince1970: 5))
    #expect(records.last?.startedAt == Date(timeIntervalSince1970: 104))
}
