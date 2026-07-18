import Foundation
import Testing
@testable import StayPane

@MainActor
@Test func diagnosticLogRedactsPrivateContentAndNetworkLocations() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("StayPaneDiagnosticRedactionTests")
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = DiagnosticLog(
        fileURL: directory.appendingPathComponent("diagnostics.json"),
        now: { Date(timeIntervalSince1970: 50_000) }
    )
    let privateValues = [
        "Secret Editor",
        "Confidential Window",
        "Hidden Tab"
    ]

    try log.record(
        .sessionStartFailed,
        details: "Secret Editor | Confidential Window | Hidden Tab | https://private.example.com/work?q=1 | private.example.com",
        privateValues: privateValues
    )

    let entry = try #require(log.load().first)
    let encodedEntry = String(
        decoding: try JSONEncoder().encode(entry),
        as: UTF8.self
    )
    for prohibitedValue in privateValues + [
        "https://private.example.com/work?q=1",
        "private.example.com"
    ] {
        #expect(!encodedEntry.localizedCaseInsensitiveContains(prohibitedValue))
    }
    #expect(encodedEntry.contains("[REDACTED]"))
}

@MainActor
@Test func diagnosticLogRetainsOnlyTheLatestTwoHundredEntries() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("StayPaneBoundedDiagnosticTests")
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var timestamp: TimeInterval = 0
    let log = DiagnosticLog(
        fileURL: directory.appendingPathComponent("diagnostics.json"),
        now: { Date(timeIntervalSince1970: timestamp) }
    )

    for index in 0..<205 {
        timestamp = TimeInterval(index)
        try log.record(.blockedTarget)
    }

    let entries = try log.load()
    #expect(entries.count == 200)
    #expect(entries.first?.timestamp == Date(timeIntervalSince1970: 5))
    #expect(entries.last?.timestamp == Date(timeIntervalSince1970: 204))
}

@MainActor
@Test func explicitDiagnosticsExportCreatesInspectableLocalArtifact() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("StayPaneDiagnosticExportTests")
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = DiagnosticLog(
        fileURL: directory.appendingPathComponent("diagnostics.json"),
        now: { Date(timeIntervalSince1970: 60_000) }
    )
    try log.record(
        .sessionInterrupted,
        details: "Secret App lost https://private.example.com/session",
        privateValues: ["Secret App"]
    )
    let exportURL = directory.appendingPathComponent("StayPane-Diagnostics.json")

    let writtenURL = try log.export(to: exportURL)

    #expect(writtenURL == exportURL)
    let export = try String(contentsOf: exportURL, encoding: .utf8)
    #expect(export.contains("Inspect this local artifact before sharing."))
    #expect(export.contains("sessionInterrupted"))
    for prohibitedValue in [
        "Secret App",
        "https://private.example.com/session",
        "private.example.com"
    ] {
        #expect(!export.localizedCaseInsensitiveContains(prohibitedValue))
    }
}
