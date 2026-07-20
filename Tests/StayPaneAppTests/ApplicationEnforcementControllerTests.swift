import AppKit
import ApplicationServices
import Foundation
import StayPaneCore
import StayPanePlatform
import Testing
@testable import StayPane

@MainActor
@Test func targetDisappearanceAtCountdownBoundaryPreservesDraftAndNamesTarget() throws {
    let clock = EnforcementTestClock(
        now: Date(timeIntervalSince1970: 20_000)
    )
    let resolver = FakeApplicationAvailabilityResolver(available: false)
    let controller = ApplicationEnforcementController(
        permissionClient: AccessibilityPermissionClient(),
        availabilityResolver: resolver,
        notificationCenter: NotificationCenter(),
        windowOperator: UnusedWindowOperator(),
        windowEnforcementStore: NoWindowEnforcementStore()
    )
    let engine = SessionEngine(clock: clock, enforcement: controller)
    let target = ApplicationTarget(
        displayName: "Research",
        bundleIdentifier: "com.example.research",
        applicationURL: URL(fileURLWithPath: "/Applications/Research.app")
    )

    engine.beginConfiguration()
    engine.select(target: target)
    try engine.beginStartCountdown(seconds: 3)
    clock.advance(by: 3)

    let expectedError = ApplicationEnforcementError.allowedApplicationsUnavailable(
        ["Research"]
    )
    #expect(throws: expectedError) {
        try engine.advance()
    }

    guard case let .ready(draft) = engine.state else {
        Issue.record("A disappeared target should abort enforcement")
        return
    }
    #expect(draft.targets == [.application(target)])
    #expect(expectedError.localizedDescription.contains("Research"))
    #expect(expectedError.localizedDescription.contains("no longer installed"))
}

@MainActor
@Test func enforcementRefusesToStartWithoutAccessibilityPermission() {
    let controller = ApplicationEnforcementController(
        permissionClient: FakePermissionChecker(isGranted: false),
        availabilityResolver: FakeApplicationAvailabilityResolver(available: true),
        notificationCenter: NotificationCenter(),
        windowOperator: UnusedWindowOperator(),
        windowEnforcementStore: NoWindowEnforcementStore()
    )
    let target = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor"
    )

    #expect(
        throws: ApplicationEnforcementError.accessibilityPermissionMissing
    ) {
        try controller.start(allowing: [.application(target)])
    }
}

@MainActor
@Test func selectedExactWindowIdentityIsPersistedBeforeEnforcement() throws {
    let processIdentifier: Int32 = 930
    let provider = EnforcementWindowProvider(
        descriptor: AccessibilityWindowDescriptor(
            element: AXUIElementCreateApplication(9_301),
            title: "Draft",
            role: "AXWindow",
            subrole: "AXStandardWindow",
            isModal: false,
            isFocused: true,
            parentElement: nil,
            frame: .zero,
            accessibilityIdentifier: "editor-window-930"
        )
    )
    let catalog = AccessibilityWindowCatalog(provider: provider)
    let application = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor",
        processIdentifier: processIdentifier
    )
    let selectedWindow = try #require(
        catalog.loadWindows(for: application).first
    )
    let store = FakeWindowEnforcementStore()
    let controller = ApplicationEnforcementController(
        permissionClient: FakePermissionChecker(isGranted: true),
        availabilityResolver: FakeApplicationAvailabilityResolver(available: true),
        windowCatalog: catalog,
        notificationCenter: NotificationCenter(),
        windowOperator: UnusedWindowOperator(),
        windowEnforcementStore: store,
        workspaceApplications: EmptyWorkspaceApplicationAccess()
    )

    try controller.start(allowing: [.window(selectedWindow)])
    controller.suspendForSystemTermination()

    let snapshot = try #require(store.snapshot)
    #expect(snapshot.allowedWindowReferences.map(\.windowIdentifier) == [selectedWindow.id])
    #expect(snapshot.restorationReferences.isEmpty)

    let relaunchedCatalog = AccessibilityWindowCatalog(
        provider: EnforcementWindowProvider(
            descriptor: AccessibilityWindowDescriptor(
                element: AXUIElementCreateApplication(9_302),
                title: "Renamed draft",
                role: "AXWindow",
                subrole: "AXStandardWindow",
                isModal: false,
                isFocused: true,
                parentElement: nil,
                frame: .zero,
                accessibilityIdentifier: "editor-window-930"
            )
        ),
        exactWindowReferences: snapshot.allowedWindowReferences
    )
    let reconnectedWindow = try #require(
        relaunchedCatalog.loadWindows(for: application).first
    )
    #expect(reconnectedWindow.id == selectedWindow.id)
}

@MainActor
@Test func exactWindowWithoutPersistentIdentityCannotStart() throws {
    let provider = EnforcementWindowProvider(
        descriptor: AccessibilityWindowDescriptor(
            element: AXUIElementCreateApplication(9_401),
            title: "Unstable Draft",
            role: "AXWindow",
            subrole: "AXStandardWindow",
            isModal: false,
            isFocused: true,
            parentElement: nil,
            frame: .zero
        )
    )
    let catalog = AccessibilityWindowCatalog(provider: provider)
    let application = ApplicationTarget(
        displayName: "Editor",
        bundleIdentifier: "com.example.editor",
        processIdentifier: 940
    )
    let selectedWindow = try #require(
        catalog.loadWindows(for: application).first
    )
    let controller = ApplicationEnforcementController(
        permissionClient: FakePermissionChecker(isGranted: true),
        availabilityResolver: FakeApplicationAvailabilityResolver(available: true),
        windowCatalog: catalog,
        notificationCenter: NotificationCenter(),
        windowOperator: UnusedWindowOperator(),
        windowEnforcementStore: FakeWindowEnforcementStore(),
        workspaceApplications: EmptyWorkspaceApplicationAccess()
    )

    #expect(
        throws: ApplicationEnforcementError.exactWindowIdentityUnavailable(
            ["Unstable Draft"]
        )
    ) {
        try controller.start(allowing: [.window(selectedWindow)])
    }
}

@MainActor
@Test func broadApplicationSessionMinimizesBlockedWindowUsingCoreGraphicsIdentity() throws {
    let chromeProcessIdentifier: Int32 = 3_300
    let chatProcessIdentifier: Int32 = 7_300
    let blockedElement = AXUIElementCreateApplication(73_001)
    let provider = MappedEnforcementWindowProvider(
        descriptorsByProcessIdentifier: [
            chromeProcessIdentifier: [],
            chatProcessIdentifier: [
                AccessibilityWindowDescriptor(
                    element: blockedElement,
                    title: "Conversation",
                    role: "AXWindow",
                    subrole: "AXStandardWindow",
                    isModal: false,
                    isFocused: false,
                    parentElement: nil,
                    frame: CGRect(x: 0, y: 34, width: 1_710, height: 987),
                    coreGraphicsWindowNumber: 175
                )
            ],
        ]
    )
    let operatorClient = RecordingWindowOperator()
    let store = FakeWindowEnforcementStore()
    let workspace = FixtureWorkspaceApplicationAccess(
        runningApplicationSnapshots: [
            WorkspaceApplicationSnapshot(
                displayName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                processIdentifier: chromeProcessIdentifier
            ),
            WorkspaceApplicationSnapshot(
                displayName: "Chat",
                bundleIdentifier: "com.example.chat",
                processIdentifier: chatProcessIdentifier
            ),
        ]
    )
    let controller = ApplicationEnforcementController(
        permissionClient: FakePermissionChecker(isGranted: true),
        availabilityResolver: FakeApplicationAvailabilityResolver(available: true),
        windowCatalog: AccessibilityWindowCatalog(provider: provider),
        notificationCenter: NotificationCenter(),
        windowOperator: operatorClient,
        windowEnforcementStore: store,
        workspaceApplications: workspace
    )
    let chrome = ApplicationTarget(
        displayName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome",
        processIdentifier: chromeProcessIdentifier
    )

    try controller.start(allowing: [.application(chrome)])
    controller.suspendForSystemTermination()

    #expect(operatorClient.minimizedElements.count == 1)
    #expect(provider.discoveryBatchCount == 1)
    #expect(provider.completedDiscoveryBatchCount == 1)
    let restorationReference = try #require(
        store.snapshot?.restorationReferences.first
    )
    #expect(restorationReference.bundleIdentifier == "com.example.chat")
    #expect(restorationReference.coreGraphicsWindowNumber == 175)
}

@MainActor
private final class EnforcementTestClock: SessionClock {
    var now: Date
    var continuousNow: TimeInterval = 0

    init(now: Date) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        continuousNow += seconds
    }
}

@MainActor
private final class FakeApplicationAvailabilityResolver: ApplicationAvailabilityResolving {
    let available: Bool

    init(available: Bool) {
        self.available = available
    }

    func isAvailable(_ target: ApplicationTarget) -> Bool {
        available
    }
}

@MainActor
private final class FakePermissionChecker: AccessibilityPermissionChecking {
    let isGranted: Bool

    init(isGranted: Bool) {
        self.isGranted = isGranted
    }

    func verifyWindowControl() -> Bool {
        isGranted
    }
}

@MainActor
private final class UnusedWindowOperator: AccessibilityWindowOperating {
    func minimizedState(of window: AXUIElement) -> AccessibilityWindowState {
        .failed
    }

    func setMinimized(
        _ minimized: Bool,
        for window: AXUIElement
    ) -> AccessibilityWindowWriteResult {
        .failed
    }

    func raise(_ window: AXUIElement) -> AccessibilityWindowWriteResult {
        .failed
    }
}

@MainActor
private final class EnforcementWindowProvider: AccessibilityWindowProviding {
    let descriptor: AccessibilityWindowDescriptor

    init(descriptor: AccessibilityWindowDescriptor) {
        self.descriptor = descriptor
    }

    func windows(processIdentifier: Int32) throws -> [AccessibilityWindowDescriptor] {
        [descriptor]
    }
}

@MainActor
private final class MappedEnforcementWindowProvider: AccessibilityWindowProviding {
    let descriptorsByProcessIdentifier: [Int32: [AccessibilityWindowDescriptor]]
    private(set) var discoveryBatchCount = 0
    private(set) var completedDiscoveryBatchCount = 0

    init(
        descriptorsByProcessIdentifier: [Int32: [AccessibilityWindowDescriptor]]
    ) {
        self.descriptorsByProcessIdentifier = descriptorsByProcessIdentifier
    }

    func beginWindowDiscoveryBatch() {
        discoveryBatchCount += 1
    }

    func endWindowDiscoveryBatch() {
        completedDiscoveryBatchCount += 1
    }

    func windows(processIdentifier: Int32) throws -> [AccessibilityWindowDescriptor] {
        descriptorsByProcessIdentifier[processIdentifier] ?? []
    }
}

@MainActor
private final class RecordingWindowOperator: AccessibilityWindowOperating {
    private(set) var minimizedElements: [AXUIElement] = []

    func minimizedState(of window: AXUIElement) -> AccessibilityWindowState {
        minimizedElements.contains(where: { CFEqual($0, window) })
            ? .minimized(true)
            : .minimized(false)
    }

    func setMinimized(
        _ minimized: Bool,
        for window: AXUIElement
    ) -> AccessibilityWindowWriteResult {
        if minimized {
            minimizedElements.append(window)
        } else {
            minimizedElements.removeAll(where: { CFEqual($0, window) })
        }
        return .success
    }

    func raise(_ window: AXUIElement) -> AccessibilityWindowWriteResult {
        .success
    }
}

@MainActor
private final class FixtureWorkspaceApplicationAccess: WorkspaceApplicationAccessing {
    let runningApplicationSnapshots: [WorkspaceApplicationSnapshot]
    let frontmostProcessIdentifier: Int32? = nil

    init(runningApplicationSnapshots: [WorkspaceApplicationSnapshot]) {
        self.runningApplicationSnapshots = runningApplicationSnapshots
    }

    var runningApplications: [NSRunningApplication] { [] }
    var frontmostApplication: NSRunningApplication? { nil }

    func application(processIdentifier: Int32) -> NSRunningApplication? {
        nil
    }

    func runningApplications(
        bundleIdentifier: String
    ) -> [NSRunningApplication] {
        []
    }
}

@MainActor
private final class FakeWindowEnforcementStore: WindowEnforcementPersisting {
    var snapshot: WindowEnforcementSnapshot?

    func load() throws -> WindowEnforcementSnapshot? {
        snapshot
    }

    func save(_ snapshot: WindowEnforcementSnapshot) throws {
        self.snapshot = snapshot.isEmpty ? nil : snapshot
    }

    func clear() throws {
        snapshot = nil
    }
}

@MainActor
private final class EmptyWorkspaceApplicationAccess: WorkspaceApplicationAccessing {
    var runningApplications: [NSRunningApplication] { [] }
    var frontmostApplication: NSRunningApplication? { nil }

    func application(processIdentifier: Int32) -> NSRunningApplication? {
        nil
    }

    func runningApplications(
        bundleIdentifier: String
    ) -> [NSRunningApplication] {
        []
    }
}
