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
    case unconfirmedWindowMutation
}

struct DiagnosticEntry: Codable, Equatable, Sendable {
    let timestamp: Date
    let event: DiagnosticEvent
    let details: String?
}

enum DiagnosticDetail: Sendable {
    case count(Int)
    case failure(DiagnosticFailureCode)
    case privateContent(String, privateValues: [String])
}

enum DiagnosticFailureCode: String, Sendable {
    case accessibilityPermissionMissing
    case allowedApplicationUnavailable
    case allowedWindowUnavailable
    case exactTargetIdentityUnavailable
    case restorationPending
    case windowControlUnavailable
    case windowIdentityUnavailable
    case windowPersistenceUnavailable
    case browserUnavailable
    case unknown
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

    private let entries: BoundedLocalJSONCollection<DiagnosticEntry>
    private let now: () -> Date

    init(
        fileURL: URL = DiagnosticLog.defaultFileURL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        entries = BoundedLocalJSONCollection(
            fileURL: fileURL,
            maximumCount: Self.maximumEntryCount,
            fileManager: fileManager
        )
        self.now = now
    }

    func load() throws -> [DiagnosticEntry] {
        try entries.load()
    }

    func record(
        _ event: DiagnosticEvent,
        detail: DiagnosticDetail? = nil
    ) throws {
        try entries.append(
            DiagnosticEntry(
                timestamp: now(),
                event: event,
                details: Self.persistedDetails(from: detail)
            )
        )
    }

    private static func persistedDetails(
        from detail: DiagnosticDetail?
    ) -> String? {
        switch detail {
        case let .count(count):
            "count: \(max(0, count))"
        case let .failure(code):
            "failure: \(code.rawValue)"
        case let .privateContent(value, privateValues):
            redact(value, privateValues: privateValues)
        case nil:
            nil
        }
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
            of: #"(?i)\b(?:[a-z0-9](?:[a-z0-9-]{0,62})\.)+[a-z]{2,63}\b(?:[/?:#][^\s|\"']*)?"#,
            with: "[REDACTED]",
            options: .regularExpression
        )
    }

    private static var defaultFileURL: URL {
        StayPaneStorageLocation.applicationSupportFile(
            named: "diagnostics.json"
        )
    }
}
