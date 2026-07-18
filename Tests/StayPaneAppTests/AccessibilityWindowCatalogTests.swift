import ApplicationServices
import Foundation
import StayPaneCore
import Testing
@testable import StayPane

@MainActor
@Test func closedAndReopenedWindowReceivesANewIdentity() throws {
    let originalElement = AXUIElementCreateApplication(701)
    let reopenedElement = AXUIElementCreateApplication(702)
    let provider = FakeAccessibilityWindowProvider(
        descriptors: [
            AccessibilityWindowDescriptor(
                element: originalElement,
                title: "Draft",
                role: "AXWindow",
                subrole: "AXStandardWindow",
                isModal: false,
                isFocused: true,
                parentElement: nil,
                frame: .zero
            )
        ]
    )
    let catalog = AccessibilityWindowCatalog(provider: provider)
    let application = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor",
        processIdentifier: 70
    )

    let original = try #require(catalog.loadWindows(for: application).first)
    provider.descriptors = []
    _ = try catalog.loadWindows(for: application)
    #expect(!catalog.isAvailable(original.target))

    provider.descriptors = [
        AccessibilityWindowDescriptor(
            element: reopenedElement,
            title: "Draft",
            role: "AXWindow",
            subrole: "AXStandardWindow",
            isModal: false,
            isFocused: true,
            parentElement: nil,
            frame: .zero
        )
    ]
    let reopened = try #require(catalog.loadWindows(for: application).first)

    #expect(reopened.target.title == original.target.title)
    #expect(reopened.target.id != original.target.id)
}

@MainActor
@Test func sheetIsClassifiedAsTransientOnlyThroughItsParentWindow() throws {
    let parentElement = AXUIElementCreateApplication(711)
    let sheetElement = AXUIElementCreateApplication(712)
    let provider = FakeAccessibilityWindowProvider(
        descriptors: [
            AccessibilityWindowDescriptor(
                element: parentElement,
                title: "Draft",
                role: "AXWindow",
                subrole: "AXStandardWindow",
                isModal: false,
                isFocused: false,
                parentElement: nil,
                frame: .zero
            ),
            AccessibilityWindowDescriptor(
                element: sheetElement,
                title: "Save",
                role: "AXSheet",
                subrole: nil,
                isModal: true,
                isFocused: true,
                parentElement: parentElement,
                frame: .zero
            )
        ]
    )
    let catalog = AccessibilityWindowCatalog(provider: provider)
    let application = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor",
        processIdentifier: 71
    )

    let windows = try catalog.catalogueWindows(for: application)
    let parent = try #require(windows.first { $0.target.title == "Draft" })
    let sheet = try #require(windows.first { $0.target.title == "Save" })

    #expect(
        sheet.observation.relationship
            == .transient(ancestorWindowIdentifiers: [parent.target.id])
    )
}

@MainActor
private final class FakeAccessibilityWindowProvider: AccessibilityWindowProviding {
    var descriptors: [AccessibilityWindowDescriptor]

    init(descriptors: [AccessibilityWindowDescriptor]) {
        self.descriptors = descriptors
    }

    func windows(processIdentifier: Int32) throws -> [AccessibilityWindowDescriptor] {
        descriptors
    }
}
