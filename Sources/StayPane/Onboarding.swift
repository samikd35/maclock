import Foundation

struct OnboardingProgress: Equatable {
    var isCompleted = false
    var hasRequestedAccessibility = false
    var hadVerifiedAccessibility = false
}

final class OnboardingProgressStore {
    private enum Key {
        static let completed = "hasCompletedFirstRunOnboarding"
        static let accessibilityRequested = "hasRequestedAccessibilityAccess"
        static let accessibilityVerified = "hasVerifiedAccessibilityAccess"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> OnboardingProgress {
        OnboardingProgress(
            isCompleted: defaults.bool(forKey: Key.completed),
            hasRequestedAccessibility: defaults.bool(
                forKey: Key.accessibilityRequested
            ),
            hadVerifiedAccessibility: defaults.bool(
                forKey: Key.accessibilityVerified
            )
        )
    }

    func markAccessibilityRequested() {
        defaults.set(true, forKey: Key.accessibilityRequested)
    }

    func markAccessibilityVerified() {
        defaults.set(true, forKey: Key.accessibilityVerified)
    }

    func markCompleted() {
        defaults.set(true, forKey: Key.completed)
    }
}

final class InstalledAccessibilityMigrationStore {
    private static let completionKey =
        "hasCompletedInstalledAccessibilityMigration"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isCompleted: Bool {
        defaults.bool(forKey: Self.completionKey)
    }

    func markCompleted() {
        defaults.set(true, forKey: Self.completionKey)
    }

    static func isInstalledApplication(
        bundleURL: URL,
        homeDirectoryURL: URL
    ) -> Bool {
        let installedURL = homeDirectoryURL
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("StayPane.app", isDirectory: true)
        return bundleURL.resolvingSymlinksInPath().standardizedFileURL
            == installedURL.resolvingSymlinksInPath().standardizedFileURL
    }

    static func shouldPresent(
        isInstalledApplication: Bool,
        accessibilityVerified: Bool,
        migrationCompleted: Bool
    ) -> Bool {
        isInstalledApplication
            && !accessibilityVerified
            && !migrationCompleted
    }
}

struct AccessibilityVerificationResult: Equatable {
    let isAuthorized: Bool
    let verificationSucceeded: Bool
    let setupState: AccessibilitySetupState
}

@MainActor
struct AccessibilityOnboardingWorkflow {
    let progressStore: OnboardingProgressStore
    let client: any AccessibilityOnboardingAccessing

    var progress: OnboardingProgress {
        progressStore.load()
    }

    var canDismissOnboarding: Bool {
        progress.isCompleted
    }

    func requestAccess() {
        progressStore.markAccessibilityRequested()
        client.requestAccess()
        client.openSystemSettings()
    }

    func verify(
        previousVerificationSucceeded: Bool,
        forceVerification: Bool
    ) -> AccessibilityVerificationResult {
        let isAuthorized = client.isGranted
        let verificationSucceeded: Bool
        if isAuthorized {
            verificationSucceeded = forceVerification
                || !previousVerificationSucceeded
                ? client.verifyWindowControl()
                : previousVerificationSucceeded
        } else {
            verificationSucceeded = false
        }
        if verificationSucceeded {
            progressStore.markAccessibilityVerified()
        }
        return AccessibilityVerificationResult(
            isAuthorized: isAuthorized,
            verificationSucceeded: verificationSucceeded,
            setupState: AccessibilitySetupState.resolve(
                progress: progressStore.load(),
                isAuthorized: isAuthorized,
                verificationSucceeded: verificationSucceeded
            )
        )
    }

    func complete(_ checklist: OnboardingChecklist) -> Bool {
        guard checklist.canFinish else {
            return false
        }
        progressStore.markCompleted()
        return true
    }
}

enum AccessibilitySetupState: Equatable {
    case notRequested
    case accessNotGranted
    case enabledButUnverified
    case verified
    case revoked

    static func resolve(
        progress: OnboardingProgress,
        isAuthorized: Bool,
        verificationSucceeded: Bool
    ) -> Self {
        if isAuthorized {
            return verificationSucceeded ? .verified : .enabledButUnverified
        }
        if progress.hadVerifiedAccessibility {
            return .revoked
        }
        return progress.hasRequestedAccessibility
            ? .accessNotGranted
            : .notRequested
    }

    var title: String {
        switch self {
        case .notRequested:
            "Not Requested"
        case .accessNotGranted:
            "Access Not Granted"
        case .enabledButUnverified:
            "Enabled but Unverified"
        case .verified:
            "Verified"
        case .revoked:
            "Revoked"
        }
    }

    var guidance: String {
        switch self {
        case .notRequested:
            "Review why Accessibility is needed, then open the correct System Settings page."
        case .accessNotGranted:
            "StayPane cannot start enforcement until you enable Accessibility and return to Check Again."
        case .enabledButUnverified:
            "Permission is enabled, but the Harmless Window-Control Verification did not succeed. Open a normal app window and run it again."
        case .verified:
            "StayPane successfully completed the Harmless Window-Control Verification."
        case .revoked:
            "StayPane detected that previously verified access disappeared. Active enforcement uses Fail Open; grant access again before another Session."
        }
    }
}

struct ChromeProfileSetupSummary: Equatable {
    let readyCount: Int
    let synchronizingCount: Int
    let needsAttentionCount: Int

    var readyStatusTitle: String {
        [
            profileCount(readyCount, status: "Ready"),
            synchronizingCount > 0
                ? profileCount(synchronizingCount, status: "Synchronizing")
                : nil,
            needsAttentionCount > 0
                ? profileCount(needsAttentionCount, status: "Needs Attention")
                : nil,
        ]
        .compactMap { $0 }
        .joined(separator: "; ")
    }

    private func profileCount(_ count: Int, status: String) -> String {
        "\(count) \(count == 1 ? "Profile" : "Profiles") \(status)"
    }
}

@MainActor
protocol ChromeConnectionPolling: AnyObject {
    func poll() throws
}

enum ChromeConnectionTestOutcome: Equatable {
    case nativeBridgeUnavailable
    case pollFailed
    case polled
}

@MainActor
struct ChromeConnectionWorkflow {
    let bridge: (any ChromeConnectionPolling)?

    func testConnection() -> ChromeConnectionTestOutcome {
        guard let bridge else {
            return .nativeBridgeUnavailable
        }
        do {
            try bridge.poll()
            return .polled
        } catch {
            return .pollFailed
        }
    }
}

extension NativeBridgeController: ChromeConnectionPolling {}

enum ChromeSetupState: Equatable {
    case nativeBridgeUnavailable
    case nativeHostNotRegistered
    case waitingForProfileConnection
    case synchronizing
    case connectedProfileNeedsAttention
    case ready(ChromeProfileSetupSummary)

    static func resolve(
        nativeBridgeAvailable: Bool,
        nativeHostRegistered: Bool,
        profileSummary: ChromeProfileSetupSummary
    ) -> Self {
        guard nativeBridgeAvailable else {
            return .nativeBridgeUnavailable
        }
        guard nativeHostRegistered else {
            return .nativeHostNotRegistered
        }
        if profileSummary.readyCount > 0 {
            return .ready(profileSummary)
        }
        if profileSummary.needsAttentionCount > 0 {
            return .connectedProfileNeedsAttention
        }
        if profileSummary.synchronizingCount > 0 {
            return .synchronizing
        }
        return .waitingForProfileConnection
    }

    var title: String {
        switch self {
        case .nativeBridgeUnavailable:
            "Native Bridge Unavailable"
        case .nativeHostNotRegistered:
            "Native Host Not Registered — Optional"
        case .waitingForProfileConnection:
            "Waiting for Profile Connection"
        case .synchronizing:
            "Synchronizing"
        case .connectedProfileNeedsAttention:
            "Connected Profile Needs Attention"
        case let .ready(summary):
            summary.readyStatusTitle
        }
    }

    var guidance: String {
        switch self {
        case .nativeBridgeUnavailable:
            "StayPane could not start its local Native Bridge. Rebuild the app package, then reopen StayPane before testing Chrome setup again."
        case .nativeHostNotRegistered:
            "Skip Chrome when using native Application Targets or Window Targets. Configure it only for Browser Window Targets or Tab Targets."
        case .waitingForProfileConnection:
            "Load the unpacked companion in a Chrome Profile, enable Allow in Incognito, then test the local connection."
        case .synchronizing:
            "The local connection is verified and its first current Tab Snapshot is arriving."
        case .connectedProfileNeedsAttention:
            "Open the companion details in chrome://extensions and enable Allow in Incognito. Incognito tabs remain unselectable."
        case .ready:
            "The extension identity, Native Bridge, and required browser capability are verified locally."
        }
    }
}

enum OnboardingChecklistStatus: Equatable {
    case complete
    case needsAttention
    case inProgress
    case optional
}

struct OnboardingChecklist: Equatable {
    let accessibility: AccessibilitySetupState
    let chrome: ChromeSetupState

    var canFinish: Bool {
        accessibility == .verified
    }

    var accessibilityStatus: OnboardingChecklistStatus {
        accessibility == .verified ? .complete : .needsAttention
    }

    var chromeStatus: OnboardingChecklistStatus {
        switch chrome {
        case .nativeBridgeUnavailable:
            .needsAttention
        case .nativeHostNotRegistered:
            .optional
        case .waitingForProfileConnection, .synchronizing:
            .inProgress
        case .connectedProfileNeedsAttention:
            .needsAttention
        case .ready:
            .complete
        }
    }
}
