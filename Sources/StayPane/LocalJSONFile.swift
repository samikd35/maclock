import Foundation

@MainActor
final class LocalJSONFile<Value: Codable> {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() throws -> Value? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try decoder.decode(Value.self, from: Data(contentsOf: fileURL))
    }

    func save(_ value: Value) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(value).write(to: fileURL, options: .atomic)
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
}

@MainActor
final class BoundedLocalJSONCollection<Element: Codable> {
    private let file: LocalJSONFile<[Element]>
    private let maximumCount: Int

    init(
        fileURL: URL,
        maximumCount: Int,
        fileManager: FileManager = .default
    ) {
        file = LocalJSONFile(fileURL: fileURL, fileManager: fileManager)
        self.maximumCount = maximumCount
    }

    func load() throws -> [Element] {
        try file.load() ?? []
    }

    func append(_ element: Element) throws {
        var elements = try load()
        elements.append(element)
        try file.save(Array(elements.suffix(maximumCount)))
    }

    func clear() throws {
        try file.clear()
    }
}

enum StayPaneStorageLocation {
    static func applicationSupportFile(named fileName: String) -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("StayPane", isDirectory: true)
        .appendingPathComponent(fileName, isDirectory: false)
    }
}
