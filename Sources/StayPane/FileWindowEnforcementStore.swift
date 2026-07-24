import Foundation

struct WindowEnforcementSnapshot: Codable, Equatable, Sendable {
    let allowedWindowReferences: [ExactWindowReference]
    let restorationReferences: [ExactWindowReference]
    let pendingMutationReference: ExactWindowReference?

    init(
        allowedWindowReferences: [ExactWindowReference],
        restorationReferences: [ExactWindowReference],
        pendingMutationReference: ExactWindowReference? = nil
    ) {
        self.allowedWindowReferences = allowedWindowReferences
        self.restorationReferences = restorationReferences
        self.pendingMutationReference = pendingMutationReference
    }

    var isEmpty: Bool {
        allowedWindowReferences.isEmpty
            && restorationReferences.isEmpty
            && pendingMutationReference == nil
    }
}

@MainActor
protocol WindowEnforcementPersisting: AnyObject {
    func load() throws -> WindowEnforcementSnapshot?
    func save(_ snapshot: WindowEnforcementSnapshot) throws
    func clear() throws
}

@MainActor
final class FileWindowEnforcementStore: WindowEnforcementPersisting {
    private let file: LocalJSONFile<WindowEnforcementSnapshot>

    init(
        fileURL: URL = FileWindowEnforcementStore.defaultFileURL,
        fileManager: FileManager = .default
    ) {
        file = LocalJSONFile(fileURL: fileURL, fileManager: fileManager)
    }

    func load() throws -> WindowEnforcementSnapshot? {
        try file.load()
    }

    func save(_ snapshot: WindowEnforcementSnapshot) throws {
        if snapshot.isEmpty {
            try file.clear()
        } else {
            try file.save(snapshot)
        }
    }

    func clear() throws {
        try file.clear()
    }

    private static var defaultFileURL: URL {
        StayPaneStorageLocation.applicationSupportFile(
            named: "window-enforcement.json"
        )
    }
}

@MainActor
final class NoWindowEnforcementStore: WindowEnforcementPersisting {
    func load() throws -> WindowEnforcementSnapshot? {
        nil
    }

    func save(_ snapshot: WindowEnforcementSnapshot) throws {}

    func clear() throws {}
}
