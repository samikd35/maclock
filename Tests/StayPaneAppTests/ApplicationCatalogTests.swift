import Foundation
import Testing
@testable import StayPane

@MainActor
@Test func closedInstalledApplicationCanBeAddedFromItsBundle() throws {
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let applicationURL = temporaryDirectory
        .appendingPathComponent("Research.app", isDirectory: true)
    let contentsURL = applicationURL
        .appendingPathComponent("Contents", isDirectory: true)
    try fileManager.createDirectory(
        at: contentsURL,
        withIntermediateDirectories: true
    )
    defer { try? fileManager.removeItem(at: temporaryDirectory) }

    let propertyList: [String: Any] = [
        "CFBundleIdentifier": "com.example.research",
        "CFBundleName": "Research"
    ]
    let propertyListData = try PropertyListSerialization.data(
        fromPropertyList: propertyList,
        format: .xml,
        options: 0
    )
    try propertyListData.write(
        to: contentsURL.appendingPathComponent("Info.plist")
    )

    let catalog = ApplicationCatalog()
    let item = try catalog.loadApplication(at: applicationURL)

    #expect(item.target.displayName == "Research")
    #expect(item.target.bundleIdentifier == "com.example.research")
    #expect(item.target.processIdentifier == nil)
    #expect(item.target.applicationURL == applicationURL.standardizedFileURL)
    #expect(item.availability == .installed)

    try fileManager.removeItem(at: applicationURL)
    let unavailableItem = catalog.refresh(item)
    #expect(unavailableItem.availability == .unavailable)
    #expect(!catalog.isAvailable(item.target))
}
