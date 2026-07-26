import Foundation
import Testing
@testable import StayPane

@Test func onboardingProgressPersistsFirstRunMilestones() throws {
    let suiteName = "StayPaneOnboardingTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = OnboardingProgressStore(defaults: defaults)

    #expect(store.load() == OnboardingProgress())

    store.markAccessibilityRequested()
    store.markAccessibilityVerified()
    store.markCompleted()

    #expect(
        OnboardingProgressStore(defaults: defaults).load()
            == OnboardingProgress(
                isCompleted: true,
                hasRequestedAccessibility: true,
                hadVerifiedAccessibility: true
            )
    )
}

@Test func installedAccessibilityMigrationIsIndependentAndPathSpecific() throws {
    let suiteName =
        "StayPaneInstalledAccessibilityMigrationTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = InstalledAccessibilityMigrationStore(defaults: defaults)
    let homeURL = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let installedURL = homeURL
        .appendingPathComponent("Applications", isDirectory: true)
        .appendingPathComponent("StayPane.app", isDirectory: true)
    let developmentURL = homeURL
        .appendingPathComponent("Source/.build/StayPane.app")

    #expect(
        InstalledAccessibilityMigrationStore.isInstalledApplication(
            bundleURL: installedURL,
            homeDirectoryURL: homeURL
        )
    )
    #expect(
        !InstalledAccessibilityMigrationStore.isInstalledApplication(
            bundleURL: developmentURL,
            homeDirectoryURL: homeURL
        )
    )
    #expect(
        InstalledAccessibilityMigrationStore.shouldPresent(
            isInstalledApplication: true,
            accessibilityVerified: false,
            migrationCompleted: store.isCompleted
        )
    )

    store.markCompleted()

    #expect(store.isCompleted)
    #expect(
        !InstalledAccessibilityMigrationStore.shouldPresent(
            isInstalledApplication: true,
            accessibilityVerified: false,
            migrationCompleted: store.isCompleted
        )
    )
    #expect(
        !InstalledAccessibilityMigrationStore.shouldPresent(
            isInstalledApplication: true,
            accessibilityVerified: true,
            migrationCompleted: false
        )
    )
}

@Test func accessibilitySetupDistinguishesEveryPermissionOutcome() {
    #expect(
        AccessibilitySetupState.resolve(
            progress: OnboardingProgress(),
            isAuthorized: false,
            verificationSucceeded: false
        ) == .notRequested
    )
    #expect(
        AccessibilitySetupState.resolve(
            progress: OnboardingProgress(
                hasRequestedAccessibility: true
            ),
            isAuthorized: false,
            verificationSucceeded: false
        ) == .accessNotGranted
    )
    #expect(
        AccessibilitySetupState.resolve(
            progress: OnboardingProgress(),
            isAuthorized: true,
            verificationSucceeded: false
        ) == .enabledButUnverified
    )
    #expect(
        AccessibilitySetupState.resolve(
            progress: OnboardingProgress(),
            isAuthorized: true,
            verificationSucceeded: true
        ) == .verified
    )
    #expect(
        AccessibilitySetupState.resolve(
            progress: OnboardingProgress(
                hadVerifiedAccessibility: true
            ),
            isAuthorized: false,
            verificationSucceeded: false
        ) == .revoked
    )
}

@Test func staleAccessibilityVerificationCannotCompleteOnboarding() {
    let staleState = AccessibilitySetupState.resolve(
        progress: OnboardingProgress(
            hasRequestedAccessibility: true,
            hadVerifiedAccessibility: true
        ),
        isAuthorized: true,
        verificationSucceeded: false
    )
    let checklist = OnboardingChecklist(
        accessibility: staleState,
        chrome: .nativeHostNotRegistered
    )

    #expect(staleState == .enabledButUnverified)
    #expect(!checklist.canFinish)
    #expect(checklist.accessibilityStatus == .needsAttention)
}

@Test func successfulHarmlessVerificationCompletesRequiredSetup() {
    let verifiedState = AccessibilitySetupState.resolve(
        progress: OnboardingProgress(hasRequestedAccessibility: true),
        isAuthorized: true,
        verificationSucceeded: true
    )
    let checklist = OnboardingChecklist(
        accessibility: verifiedState,
        chrome: .nativeHostNotRegistered
    )

    #expect(verifiedState == .verified)
    #expect(checklist.canFinish)
    #expect(checklist.accessibilityStatus == .complete)
}

@MainActor
@Test func onboardingWorkflowDrivesPermissionEffectsAndPersistsVerification() throws {
    let suiteName = "StayPaneOnboardingWorkflowTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let progressStore = OnboardingProgressStore(defaults: defaults)
    let client = FakeAccessibilityOnboardingClient()
    let workflow = AccessibilityOnboardingWorkflow(
        progressStore: progressStore,
        client: client
    )

    #expect(!workflow.canDismissOnboarding)

    workflow.requestAccess()
    #expect(client.requestCount == 1)
    #expect(client.openSettingsCount == 1)
    #expect(workflow.progress.hasRequestedAccessibility)

    let denied = workflow.verify(
        previousVerificationSucceeded: false,
        forceVerification: true
    )
    #expect(denied.setupState == .accessNotGranted)
    #expect(client.verificationCount == 0)

    client.isGranted = true
    client.verificationResult = true
    let verified = workflow.verify(
        previousVerificationSucceeded: false,
        forceVerification: true
    )
    #expect(verified.setupState == .verified)
    #expect(client.verificationCount == 1)
    #expect(workflow.progress.hadVerifiedAccessibility)

    let checklist = OnboardingChecklist(
        accessibility: verified.setupState,
        chrome: .nativeHostNotRegistered
    )
    #expect(workflow.complete(checklist))
    #expect(workflow.progress.isCompleted)
    #expect(workflow.canDismissOnboarding)

    client.isGranted = false
    let revoked = workflow.verify(
        previousVerificationSucceeded: true,
        forceVerification: false
    )
    #expect(revoked.setupState == .revoked)
}

@Test func ChromeSetupIsOptionalUntilABrowserTargetIsChosen() {
    let checklist = OnboardingChecklist(
        accessibility: .verified,
        chrome: .nativeHostNotRegistered
    )

    #expect(checklist.canFinish)
    #expect(checklist.accessibilityStatus == .complete)
    #expect(checklist.chromeStatus == .optional)
}

@Test func ChromeSetupSummarizesConnectionVerificationWithoutHidingFailures() {
    #expect(
        ChromeSetupState.resolve(
            nativeBridgeAvailable: false,
            nativeHostRegistered: false,
            profileSummary: ChromeProfileSetupSummary(
                readyCount: 0,
                synchronizingCount: 0,
                needsAttentionCount: 0
            )
        ) == .nativeBridgeUnavailable
    )
    #expect(
        ChromeSetupState.resolve(
            nativeBridgeAvailable: true,
            nativeHostRegistered: false,
            profileSummary: ChromeProfileSetupSummary(
                readyCount: 0,
                synchronizingCount: 0,
                needsAttentionCount: 0
            )
        ) == .nativeHostNotRegistered
    )
    #expect(
        ChromeSetupState.resolve(
            nativeBridgeAvailable: true,
            nativeHostRegistered: true,
            profileSummary: ChromeProfileSetupSummary(
                readyCount: 0,
                synchronizingCount: 0,
                needsAttentionCount: 0
            )
        ) == .waitingForProfileConnection
    )
    #expect(
        ChromeSetupState.resolve(
            nativeBridgeAvailable: true,
            nativeHostRegistered: true,
            profileSummary: ChromeProfileSetupSummary(
                readyCount: 0,
                synchronizingCount: 1,
                needsAttentionCount: 0
            )
        ) == .synchronizing
    )
    #expect(
        ChromeSetupState.resolve(
            nativeBridgeAvailable: true,
            nativeHostRegistered: true,
            profileSummary: ChromeProfileSetupSummary(
                readyCount: 0,
                synchronizingCount: 0,
                needsAttentionCount: 1
            )
        ) == .connectedProfileNeedsAttention
    )
    #expect(
        ChromeSetupState.resolve(
            nativeBridgeAvailable: true,
            nativeHostRegistered: true,
            profileSummary: ChromeProfileSetupSummary(
                readyCount: 2,
                synchronizingCount: 1,
                needsAttentionCount: 1
            )
        ) == .ready(
            ChromeProfileSetupSummary(
                readyCount: 2,
                synchronizingCount: 1,
                needsAttentionCount: 1
            )
        )
    )
    #expect(
        ChromeProfileSetupSummary(
            readyCount: 2,
            synchronizingCount: 1,
            needsAttentionCount: 1
        ).readyStatusTitle
            == "2 Profiles Ready; 1 Profile Synchronizing; 1 Profile Needs Attention"
    )
}

@MainActor
@Test func ChromeConnectionWorkflowReportsMissingFailedAndSuccessfulTests() {
    #expect(
        ChromeConnectionWorkflow(bridge: nil).testConnection()
            == .nativeBridgeUnavailable
    )

    let bridge = FakeChromeConnectionPoller()
    bridge.error = FakeChromeConnectionError.failed
    #expect(
        ChromeConnectionWorkflow(bridge: bridge).testConnection()
            == .pollFailed
    )
    #expect(bridge.pollCount == 1)

    bridge.error = nil
    #expect(
        ChromeConnectionWorkflow(bridge: bridge).testConnection()
            == .polled
    )
    #expect(bridge.pollCount == 2)
}

@MainActor
private final class FakeAccessibilityOnboardingClient:
    AccessibilityOnboardingAccessing
{
    var isGranted = false
    var verificationResult = false
    private(set) var requestCount = 0
    private(set) var openSettingsCount = 0
    private(set) var verificationCount = 0

    func verifyWindowControl() -> Bool {
        verificationCount += 1
        return verificationResult
    }

    func requestAccess() -> Bool {
        requestCount += 1
        return true
    }

    func openSystemSettings() {
        openSettingsCount += 1
    }
}

private enum FakeChromeConnectionError: Error {
    case failed
}

@MainActor
private final class FakeChromeConnectionPoller: ChromeConnectionPolling {
    var error: Error?
    private(set) var pollCount = 0

    func poll() throws {
        pollCount += 1
        if let error {
            throw error
        }
    }
}
