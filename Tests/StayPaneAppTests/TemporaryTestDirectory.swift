import Foundation

struct TemporaryTestDirectory {
    let url: URL

    init(named name: String) {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathComponent(UUID().uuidString)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
