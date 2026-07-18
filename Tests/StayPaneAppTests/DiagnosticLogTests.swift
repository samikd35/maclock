import Foundation
import Testing
@testable import StayPane

@MainActor
@Test func diagnosticLogRedactsPrivateContentAndNetworkLocations() throws {
    let directory = TemporaryTestDirectory(
        named: "StayPaneDiagnosticRedactionTests"
    )
    defer { directory.remove() }
    let log = DiagnosticLog(
        fileURL: directory.url.appendingPathComponent("diagnostics.json"),
        now: { Date(timeIntervalSince1970: 50_000) }
    )
    let privateValues = [
        "Secret Editor",
        "Confidential Window",
        "Hidden Tab"
    ]

    try log.record(
        .sessionStartFailed,
        detail: .privateContent(
            "Secret Editor | Confidential Window | Hidden Tab | https://private.example.com/work?q=1 | private.example.com",
            privateValues: privateValues
        )
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
@Test func diagnosticLogRedactsBareDomainPathsAndQueries() throws {
    let directory = TemporaryTestDirectory(
        named: "StayPaneBareDomainRedactionTests"
    )
    defer { directory.remove() }
    let log = DiagnosticLog(
        fileURL: directory.url.appendingPathComponent("diagnostics.json")
    )

    try log.record(
        .sessionStartFailed,
        detail: .privateContent(
            "private.example.com/secret/project?q=BoardAcquisition",
            privateValues: []
        )
    )

    let encodedEntry = String(
        decoding: try JSONEncoder().encode(try #require(log.load().first)),
        as: UTF8.self
    )
    #expect(!encodedEntry.contains("private.example.com"))
    #expect(!encodedEntry.contains("secret/project"))
    #expect(!encodedEntry.contains("BoardAcquisition"))
}

@MainActor
@Test func diagnosticLogRetainsOnlyTheLatestTwoHundredEntries() throws {
    let directory = TemporaryTestDirectory(
        named: "StayPaneBoundedDiagnosticTests"
    )
    defer { directory.remove() }
    var timestamp: TimeInterval = 0
    let log = DiagnosticLog(
        fileURL: directory.url.appendingPathComponent("diagnostics.json"),
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
    let directory = TemporaryTestDirectory(
        named: "StayPaneDiagnosticExportTests"
    )
    defer { directory.remove() }
    let log = DiagnosticLog(
        fileURL: directory.url.appendingPathComponent("diagnostics.json"),
        now: { Date(timeIntervalSince1970: 60_000) }
    )
    try log.record(
        .sessionInterrupted,
        detail: .privateContent(
            "Secret App lost https://private.example.com/session",
            privateValues: ["Secret App"]
        )
    )
    let exportURL = directory.url.appendingPathComponent("StayPane-Diagnostics.json")

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
