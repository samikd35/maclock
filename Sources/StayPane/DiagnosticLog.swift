import Foundation

enum DiagnosticEvent: String, Codable, Equatable, Sendable {
    case applicationLaunched
    case blockedTarget
    case recoveryResumed
    case recoveryCompletedOffline
    case sessionStartFailed
    case sessionCompleted
    case sessionEndedEarly
    case sessionInterrupted
    case restorationPending
    case restorationRecovered
}

struct DiagnosticEntry: Codable, Equatable, Sendable {
    let timestamp: Date
    let event: DiagnosticEvent
    let details: String?
}

@MainActor
final class DiagnosticLog {
    private struct ExportArtifact: Codable {
        let formatVersion: Int
        let generatedAt: Date
        let privacyNotice: String
        let entries: [DiagnosticEntry]
    }

    private static let maximumEntryCount = 200

    private let file: LocalJSONFile<[DiagnosticEntry]>
    private let now: () -> Date

    init(
        fileURL: URL = DiagnosticLog.defaultFileURL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        file = LocalJSONFile(fileURL: fileURL, fileManager: fileManager)
        self.now = now
    }

    func load() throws -> [DiagnosticEntry] {
        try file.load() ?? []
    }

    func record(
        _ event: DiagnosticEvent,
        details: String? = nil,
        privateValues: [String] = []
    ) throws {
        var entries = try load()
        entries.append(
            DiagnosticEntry(
                timestamp: now(),
                event: event,
                details: details.map {
                    Self.redact($0, privateValues: privateValues)
                }
            )
        )
        try file.save(Array(entries.suffix(Self.maximumEntryCount)))
    }

    func export(to fileURL: URL) throws -> URL {
        let exportFile = LocalJSONFile<ExportArtifact>(fileURL: fileURL)
        try exportFile.save(
            ExportArtifact(
                formatVersion: 1,
                generatedAt: now(),
                privacyNotice: "Inspect this local artifact before sharing.",
                entries: try load()
            )
        )
        return fileURL
    }

    private static func redact(
        _ value: String,
        privateValues: [String]
    ) -> String {
        var redacted = value
        for privateValue in privateValues where !privateValue.isEmpty {
            redacted = redacted.replacingOccurrences(
                of: privateValue,
                with: "[REDACTED]",
                options: [.caseInsensitive, .literal]
            )
        }
        redacted = redacted.replacingOccurrences(
            of: #"(?i)\b[a-z][a-z0-9+.-]*://[^\s|\"']+"#,
            with: "[REDACTED]",
            options: .regularExpression
        )
        return redacted.replacingOccurrences(
            of: #"(?i)\b(?:[a-z0-9](?:[a-z0-9-]{0,62})\.)+[a-z]{2,63}\b"#,
            with: "[REDACTED]",
            options: .regularExpression
        )
    }

    private static var defaultFileURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("StayPane", isDirectory: true)
        .appendingPathComponent("diagnostics.json", isDirectory: false)
    }
}
