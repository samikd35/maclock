import ApplicationServices
import Foundation
import StayPaneCore
import Testing
@testable import StayPane

@MainActor
@Test func coreGraphicsInventoryIsCapturedOncePerDiscoveryBatch() {
    let observer = CountingCoreGraphicsWindowObserver(
        observations: [
            CoreGraphicsWindowObservation(
                processIdentifier: 73,
                windowNumber: 175,
                frame: CGRect(x: 0, y: 34, width: 1_710, height: 987)
            ),
            CoreGraphicsWindowObservation(
                processIdentifier: 74,
                windowNumber: 176,
                frame: CGRect(x: 20, y: 40, width: 800, height: 600)
            ),
        ]
    )
    let inventory = CoreGraphicsWindowInventory(observer: observer)

    inventory.beginDiscoveryBatch()
    #expect(inventory.observations(processIdentifier: 73).count == 1)
    #expect(inventory.observations(processIdentifier: 74).count == 1)
    inventory.endDiscoveryBatch()

    #expect(observer.captureCount == 1)
}

@Test func coreGraphicsWindowIdentityRequiresOneMatchingProcessAndFrame() {
    let expectedFrame = CGRect(x: 0, y: 34, width: 1_710, height: 987)
    let observations = [
        CoreGraphicsWindowObservation(
            processIdentifier: 73,
            windowNumber: 175,
            frame: expectedFrame
        ),
        CoreGraphicsWindowObservation(
            processIdentifier: 74,
            windowNumber: 176,
            frame: expectedFrame
        ),
        CoreGraphicsWindowObservation(
            processIdentifier: 73,
            windowNumber: 177,
            frame: CGRect(x: 20, y: 40, width: 800, height: 600)
        ),
    ]

    #expect(
        CoreGraphicsWindowIdentityResolver.windowNumber(
            processIdentifier: 73,
            frame: expectedFrame,
            observations: observations
        ) == 175
    )
    #expect(
        CoreGraphicsWindowIdentityResolver.windowNumber(
            processIdentifier: 73,
            frame: expectedFrame,
            observations: observations + [
                CoreGraphicsWindowObservation(
                    processIdentifier: 73,
                    windowNumber: 178,
                    frame: expectedFrame
                )
            ]
        ) == nil
    )
}

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
    #expect(!catalog.isAvailable(original))

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

    #expect(reopened.title == original.title)
    #expect(reopened.id != original.id)
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
@Test func attachedUtilityIsTransientButAnOrdinarySystemDialogIsNotExempt() throws {
    let parentElement = AXUIElementCreateApplication(721)
    let utilityElement = AXUIElementCreateApplication(722)
    let dialogElement = AXUIElementCreateApplication(723)
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
                element: utilityElement,
                title: "Inspector",
                role: "AXWindow",
                subrole: "AXFloatingWindow",
                isModal: false,
                isFocused: false,
                parentElement: parentElement,
                frame: .zero
            ),
            AccessibilityWindowDescriptor(
                element: dialogElement,
                title: "Unrelated Dialog",
                role: "AXWindow",
                subrole: "AXSystemDialog",
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
        processIdentifier: 72
    )

    let windows = try catalog.catalogueWindows(for: application)
    let parent = try #require(windows.first { $0.target.title == "Draft" })
    let utility = try #require(windows.first { $0.target.title == "Inspector" })
    let dialog = try #require(windows.first { $0.target.title == "Unrelated Dialog" })

    #expect(
        utility.observation.relationship
            == .transient(ancestorWindowIdentifiers: [parent.target.id])
    )
    #expect(dialog.observation.relationship == .independent)
}

@MainActor
@Test func survivingWindowIdentityReconnectsWithoutMatchingItsTitle() throws {
    let application = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor",
        processIdentifier: 73
    )
    let originalProvider = FakeAccessibilityWindowProvider(
        descriptors: [
            AccessibilityWindowDescriptor(
                element: AXUIElementCreateApplication(731),
                title: "Original title",
                role: "AXWindow",
                subrole: "AXStandardWindow",
                isModal: false,
                isFocused: true,
                parentElement: nil,
                frame: .zero,
                accessibilityIdentifier: "editor-window-73"
            )
        ]
    )
    let originalCatalog = AccessibilityWindowCatalog(provider: originalProvider)
    let originalWindow = try #require(
        originalCatalog.catalogueWindows(for: application).first
    )
    let exactReference = try #require(originalWindow.exactReference)

    let relaunchedProvider = FakeAccessibilityWindowProvider(
        descriptors: [
            AccessibilityWindowDescriptor(
                element: AXUIElementCreateApplication(732),
                title: "Renamed while StayPane was closed",
                role: "AXWindow",
                subrole: "AXStandardWindow",
                isModal: false,
                isFocused: true,
                parentElement: nil,
                frame: .zero,
                accessibilityIdentifier: "editor-window-73"
            )
        ]
    )
    let relaunchedCatalog = AccessibilityWindowCatalog(
        provider: relaunchedProvider,
        exactWindowReferences: [exactReference]
    )

    let reconnectedWindow = try #require(
        relaunchedCatalog.loadWindows(for: application).first
    )

    #expect(reconnectedWindow.id == originalWindow.target.id)
    #expect(reconnectedWindow.title != originalWindow.target.title)
}

@MainActor
@Test func windowWithoutAXIdentifierReconnectsUsingCoreGraphicsWindowNumber() throws {
    let application = ApplicationTarget(
        displayName: "Chat",
        bundleIdentifier: "com.example.chat",
        processIdentifier: 74
    )
    let originalProvider = FakeAccessibilityWindowProvider(
        descriptors: [
            AccessibilityWindowDescriptor(
                element: AXUIElementCreateApplication(741),
                title: "Conversation",
                role: "AXWindow",
                subrole: "AXStandardWindow",
                isModal: false,
                isFocused: true,
                parentElement: nil,
                frame: CGRect(x: 0, y: 34, width: 1_710, height: 987),
                coreGraphicsWindowNumber: 175
            )
        ]
    )
    let originalCatalog = AccessibilityWindowCatalog(provider: originalProvider)
    let originalWindow = try #require(
        originalCatalog.catalogueWindows(for: application).first
    )
    let exactReference = try #require(originalWindow.exactReference)

    #expect(exactReference.accessibilityIdentifier == nil)
    #expect(exactReference.coreGraphicsWindowNumber == 175)

    let relaunchedCatalog = AccessibilityWindowCatalog(
        provider: FakeAccessibilityWindowProvider(
            descriptors: [
                AccessibilityWindowDescriptor(
                    element: AXUIElementCreateApplication(742),
                    title: "Renamed conversation",
                    role: "AXWindow",
                    subrole: "AXStandardWindow",
                    isModal: false,
                    isFocused: true,
                    parentElement: nil,
                    frame: CGRect(x: 0, y: 34, width: 1_710, height: 987),
                    coreGraphicsWindowNumber: 175
                )
            ]
        ),
        exactWindowReferences: [exactReference]
    )
    let reconnectedWindow = try #require(
        relaunchedCatalog.loadWindows(for: application).first
    )

    #expect(reconnectedWindow.id == originalWindow.target.id)
}

@MainActor
@Test func aDuplicatedAccessibilityIdentifierIsNotTreatedAsExactIdentity() throws {
    let persistedIdentifier = WindowIdentifier()
    let application = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor",
        processIdentifier: 74
    )
    let provider = FakeAccessibilityWindowProvider(
        descriptors: [
            AccessibilityWindowDescriptor(
                element: AXUIElementCreateApplication(741),
                title: "First",
                role: "AXWindow",
                subrole: "AXStandardWindow",
                isModal: false,
                isFocused: true,
                parentElement: nil,
                frame: .zero,
                accessibilityIdentifier: "duplicated-accessibility-id"
            ),
            AccessibilityWindowDescriptor(
                element: AXUIElementCreateApplication(742),
                title: "Second",
                role: "AXWindow",
                subrole: "AXStandardWindow",
                isModal: false,
                isFocused: false,
                parentElement: nil,
                frame: .zero,
                accessibilityIdentifier: "duplicated-accessibility-id"
            )
        ]
    )
    let catalog = AccessibilityWindowCatalog(
        provider: provider,
        exactWindowReferences: [
            ExactWindowReference(
                windowIdentifier: persistedIdentifier,
                bundleIdentifier: application.bundleIdentifier,
                processIdentifier: 74,
                accessibilityIdentifier: "duplicated-accessibility-id"
            )
        ]
    )

    let windows = try catalog.loadWindows(for: application)

    #expect(windows.count == 2)
    #expect(windows.allSatisfy { $0.id != persistedIdentifier })
    #expect(Set(windows.map(\.id)).count == 2)
    #expect(
        try catalog.catalogueWindows(for: application)
            .allSatisfy { $0.exactReference == nil }
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

private final class CountingCoreGraphicsWindowObserver: CoreGraphicsWindowObserving {
    private let capturedObservations: [CoreGraphicsWindowObservation]
    private(set) var captureCount = 0

    init(observations: [CoreGraphicsWindowObservation]) {
        capturedObservations = observations
    }

    func observations() -> [CoreGraphicsWindowObservation] {
        captureCount += 1
        return capturedObservations
    }
}
