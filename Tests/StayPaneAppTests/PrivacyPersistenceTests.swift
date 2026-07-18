import Foundation
import StayPaneCore
import Testing
@testable import StayPane

@MainActor
@Test func persistedPrivacyArtifactsExcludeTargetAndBrowsingDetails() throws {
    let directory = TemporaryTestDirectory(
        named: "StayPanePrivacyPersistenceTests"
    )
    defer { directory.remove() }

    let historyURL = directory.url.appendingPathComponent("session-history.json")
    let recoveryURL = directory.url.appendingPathComponent("active-session.json")
    let diagnosticURL = directory.url.appendingPathComponent("diagnostics.json")
    let exportURL = directory.url.appendingPathComponent("diagnostics-export.json")
    let history = FileSessionHistoryStore(fileURL: historyURL)
    let recovery = FileSessionRecoveryStore(fileURL: recoveryURL)
    let clock = PrivacyTestClock(
        now: Date(timeIntervalSince1970: 70_000),
        continuousNow: 100
    )
    let privateValues = [
        "Sensitive Editor",
        "com.example.sensitive-editor",
        "Board Acquisition Notes",
        "Confidential Browser Tab",
        "https://private.example.com/acquisition?phase=1",
        "private.example.com"
    ]
    let application = ApplicationTarget(
        displayName: privateValues[0],
        bundleIdentifier: privateValues[1]
    )
    let engine = SessionEngine(
        clock: clock,
        enforcement: PrivacyTestEnforcement(),
        recoveryStore: recovery,
        historyStore: history
    )
    engine.beginConfiguration(duration: SessionDuration(seconds: 10)!)
    engine.select(
        target: .window(
            WindowTarget(
                id: WindowIdentifier(),
                title: privateValues[2],
                application: application
            )
        )
    )
    try engine.beginStartCountdown(seconds: 0)
    try engine.advance()
    #expect(FileManager.default.fileExists(atPath: recoveryURL.path))

    clock.advance(by: 10)
    try engine.advance()

    #expect(!FileManager.default.fileExists(atPath: recoveryURL.path))
    let historyObject = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: historyURL))
            as? [[String: Any]]
    )
    let historyRecord = try #require(historyObject.first)
    #expect(
        Set(historyRecord.keys) == [
            "actualFocusTime",
            "plannedDuration",
            "result",
            "startedAt"
        ]
    )

    let diagnostics = DiagnosticLog(fileURL: diagnosticURL)
    try diagnostics.record(
        .sessionCompleted,
        detail: .privateContent(
            privateValues.joined(separator: " | "),
            privateValues: privateValues
        )
    )
    _ = try diagnostics.export(to: exportURL)

    let artifactURLs = [historyURL, diagnosticURL, exportURL]
    for artifactURL in artifactURLs {
        let artifact = try String(contentsOf: artifactURL, encoding: .utf8)
        for prohibitedValue in privateValues {
            #expect(
                !artifact.localizedCaseInsensitiveContains(prohibitedValue),
                "\(artifactURL.lastPathComponent) leaked a prohibited value."
            )
        }
    }
}

@MainActor
private final class PrivacyTestClock: SessionClock {
    var now: Date
    var continuousNow: TimeInterval

    init(now: Date, continuousNow: TimeInterval) {
        self.now = now
        self.continuousNow = continuousNow
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        continuousNow += seconds
    }
}

@MainActor
private final class PrivacyTestEnforcement: SessionEnforcing {
    func start(allowing targets: [SessionTarget]) throws {}
    func refresh() throws {}
    func stop() {}
}
