import AppKit
import ApplicationServices
import StayPaneCore
import StayPanePlatform

enum ApplicationEnforcementError: LocalizedError, Equatable {
    case accessibilityPermissionMissing
    case windowControlUnavailable(String)
    case allowedApplicationsUnavailable([String])
    case allowedWindowsUnavailable([String])
    case windowRestorationPending(Int)
    case windowRecoveryUnavailable

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "Accessibility access is required before StayPane can start a session."
        case let .windowControlUnavailable(applicationName):
            "StayPane could not safely control \(applicationName)."
        case let .allowedApplicationsUnavailable(applicationNames):
            "These allowed applications are no longer installed: \(applicationNames.joined(separator: ", ")). Remove them or install them again before starting."
        case let .allowedWindowsUnavailable(windowTitles):
            "These allowed windows closed before the session started: \(windowTitles.joined(separator: ", ")). Choose their reopened windows again."
        case let .windowRestorationPending(count):
            "StayPane is still restoring \(count) window(s) from the previous session."
        case .windowRecoveryUnavailable:
            "StayPane could not load or save the window state required for reliable recovery."
        }
    }
}

@MainActor
final class ApplicationEnforcementController: NSObject, SessionEnforcing {
    private struct RecoveryProcessKey: Hashable {
        let bundleIdentifier: String
        let processIdentifier: Int32
    }

    var onBlockedApplication: ((String) -> Void)?
    var onEnforcementFailure: ((Error) -> Void)?
    var onRestorationFailure: ((Int) -> Void)?
    var onRestorationRecovered: (() -> Void)?

    var pendingRestorationCount: Int {
        max(restorationTracker.pendingCount, recoveryReferences.count)
    }

    private let permissionClient: any AccessibilityPermissionChecking
    private let availabilityResolver: any ApplicationAvailabilityResolving
    private let windowCatalog: AccessibilityWindowCatalog
    private let notificationCenter: NotificationCenter
    private let windowOperator: any AccessibilityWindowOperating
    private let restorationTracker: WindowRestorationTracker
    private let windowRecoveryStore: any WindowRecoveryPersisting
    private var allowedTargets: [SessionTarget] = []
    private var windowPolicy = WindowAllowlistPolicy(targets: [])
    private var isObserving = false
    private var lastNoticeUptime: TimeInterval = -.infinity
    private var lastFullScanUptime: TimeInterval = -.infinity
    private var recoveryReferences: [WindowIdentifier: RecoverableWindowReference]
    private var windowRecoveryLoadFailed = false

    private static let fullScanInterval: TimeInterval = 0.25

    init(
        permissionClient: any AccessibilityPermissionChecking,
        availabilityResolver: any ApplicationAvailabilityResolving,
        windowCatalog: AccessibilityWindowCatalog = AccessibilityWindowCatalog(),
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        windowOperator: any AccessibilityWindowOperating = SystemAccessibilityWindowOperator(),
        windowRecoveryStore: any WindowRecoveryPersisting = FileWindowRecoveryStore()
    ) {
        self.permissionClient = permissionClient
        self.availabilityResolver = availabilityResolver
        self.windowCatalog = windowCatalog
        self.notificationCenter = notificationCenter
        self.windowOperator = windowOperator
        self.windowRecoveryStore = windowRecoveryStore
        restorationTracker = WindowRestorationTracker(operatorClient: windowOperator)
        let loadedReferences: [RecoverableWindowReference]
        do {
            loadedReferences = try windowRecoveryStore.load()
        } catch {
            loadedReferences = []
            windowRecoveryLoadFailed = true
        }
        recoveryReferences = [:]
        for reference in loadedReferences {
            recoveryReferences[reference.windowIdentifier] = reference
        }
        windowCatalog.registerRecoveredWindowReferences(loadedReferences)
        super.init()
    }

    func start(allowing targets: [SessionTarget]) throws {
        try beginEnforcement(allowing: targets, isRecovery: false)
    }

    func resume(allowing targets: [SessionTarget]) throws {
        try beginEnforcement(allowing: targets, isRecovery: true)
    }

    private func beginEnforcement(
        allowing targets: [SessionTarget],
        isRecovery: Bool
    ) throws {
        guard !windowRecoveryLoadFailed else {
            throw ApplicationEnforcementError.windowRecoveryUnavailable
        }
        let applicationTargets = targets.compactMap { target -> ApplicationTarget? in
            guard case let .application(application) = target else {
                return nil
            }
            return application
        }
        let unavailableApplications = applicationTargets.filter {
            !availabilityResolver.isAvailable($0)
        }
        guard unavailableApplications.isEmpty else {
            throw ApplicationEnforcementError.allowedApplicationsUnavailable(
                unavailableApplications.map(\.displayName)
            )
        }
        guard permissionClient.isGranted, permissionClient.verifyWindowControl() else {
            throw ApplicationEnforcementError.accessibilityPermissionMissing
        }

        if !isRecovery {
            let unavailableWindows = windowCatalog.unavailableWindowTargets(in: targets)
            guard unavailableWindows.isEmpty else {
                throw ApplicationEnforcementError.allowedWindowsUnavailable(
                    unavailableWindows.map(\.title)
                )
            }
        }
        try resolvePersistedRestorationWindows()
        if !isRecovery, pendingRestorationCount > 0 {
            let outcome = restorationTracker.restorePendingWindows()
            try removeResolvedRecoveryReferences()
            guard outcome.pendingCount == 0 else {
                throw ApplicationEnforcementError.windowRestorationPending(
                    outcome.pendingCount
                )
            }
        }

        allowedTargets = targets
        windowPolicy = WindowAllowlistPolicy(targets: targets)
        beginObservingActivations()

        do {
            try enforceCurrentWindows()
            if !isRecovery {
                activateInitialAllowedTarget()
            }
        } catch {
            stop()
            if pendingRestorationCount > 0 {
                throw ApplicationEnforcementError.windowRestorationPending(
                    pendingRestorationCount
                )
            }
            throw error
        }
    }

    func refresh() throws {
        guard !allowedTargets.isEmpty else {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFullScanUptime >= Self.fullScanInterval else {
            return
        }
        guard permissionClient.isGranted else {
            throw ApplicationEnforcementError.accessibilityPermissionMissing
        }
        try enforceCurrentWindows()
    }

    func stop() {
        endObservingActivations()
        allowedTargets = []
        windowPolicy = WindowAllowlistPolicy(targets: [])
        lastFullScanUptime = -.infinity

        do {
            try resolvePersistedRestorationWindows()
            let outcome = restorationTracker.restorePendingWindows()
            try removeResolvedRecoveryReferences()
            if outcome.pendingCount > 0 || !recoveryReferences.isEmpty {
                onRestorationFailure?(pendingRestorationCount)
            }
        } catch {
            onRestorationFailure?(pendingRestorationCount)
        }
    }

    func retryPendingRestorations() {
        guard allowedTargets.isEmpty, pendingRestorationCount > 0 else {
            return
        }

        do {
            try resolvePersistedRestorationWindows()
            let outcome = restorationTracker.restorePendingWindows()
            try removeResolvedRecoveryReferences()
            if outcome.pendingCount == 0, recoveryReferences.isEmpty {
                onRestorationRecovered?()
            }
        } catch {
            onRestorationFailure?(pendingRestorationCount)
        }
    }

    func suspendForSystemTermination() {
        endObservingActivations()
        allowedTargets = []
        windowPolicy = WindowAllowlistPolicy(targets: [])
        lastFullScanUptime = -.infinity
    }

    @objc
    private func applicationDidActivate(_ notification: Notification) {
        guard
            !allowedTargets.isEmpty,
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            application.activationPolicy == .regular,
            let bundleIdentifier = application.bundleIdentifier,
            !AccessibilityWindowCatalog.isEssentialSystemApplication(
                bundleIdentifier: bundleIdentifier
            )
        else {
            return
        }

        do {
            let applicationTarget = makeApplicationTarget(application)
            let windows = try windowCatalog.catalogueWindows(for: applicationTarget)
            try enforce(windows: windows, applicationName: applicationTarget.displayName)

            guard let focusedWindow = windows.first(where: \.isFocused) else {
                if !isEntireApplicationAllowed(bundleIdentifier: bundleIdentifier) {
                    restoreAllowedFocus(preferredTarget: nil)
                    publishBlockedNotice(
                        "\(applicationTarget.displayName) is outside this focus session."
                    )
                }
                return
            }

            let decision = windowPolicy.handleActivation(focusedWindow.observation)
            guard case let .block(refocusTarget) = decision else {
                return
            }

            restoreAllowedFocus(preferredTarget: refocusTarget)
            publishBlockedNotice(
                "\(focusedWindow.target.title) is outside this focus session."
            )
        } catch {
            NSApplication.shared.activate(ignoringOtherApps: true)
            let reportedError: Error = pendingRestorationCount > 0
                ? ApplicationEnforcementError.windowRestorationPending(
                    pendingRestorationCount
                )
                : error
            onEnforcementFailure?(reportedError)
        }
    }

    private func beginObservingActivations() {
        guard !isObserving else {
            return
        }

        notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        isObserving = true
    }

    private func endObservingActivations() {
        guard isObserving else {
            return
        }

        notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        isObserving = false
    }

    private func enforceCurrentWindows() throws {
        lastFullScanUptime = ProcessInfo.processInfo.systemUptime
        let frontmostProcessIdentifier = NSWorkspace.shared.frontmostApplication?
            .processIdentifier
        var refocusTarget: TargetIdentifier?
        var blockedNotice: String?

        for application in NSWorkspace.shared.runningApplications where
            application.activationPolicy == .regular
                && !application.isTerminated
                && application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        {
            guard
                let bundleIdentifier = application.bundleIdentifier,
                !AccessibilityWindowCatalog.isEssentialSystemApplication(
                    bundleIdentifier: bundleIdentifier
                )
            else {
                continue
            }

            let target = makeApplicationTarget(application)
            let windows = try windowCatalog.catalogueWindows(for: target)

            if application.processIdentifier == frontmostProcessIdentifier {
                if let focusedWindow = windows.first(where: \.isFocused) {
                    if case let .block(preferredTarget) = windowPolicy.handleActivation(
                        focusedWindow.observation
                    ) {
                        refocusTarget = preferredTarget
                        blockedNotice = "\(focusedWindow.target.title) is outside this focus session."
                    }
                } else if !isEntireApplicationAllowed(
                    bundleIdentifier: bundleIdentifier
                ) {
                    blockedNotice = "\(target.displayName) is outside this focus session."
                }
            }
            try enforce(windows: windows, applicationName: target.displayName)
        }

        if let blockedNotice {
            restoreAllowedFocus(preferredTarget: refocusTarget)
            publishBlockedNotice(blockedNotice)
        }
    }

    private func isEntireApplicationAllowed(bundleIdentifier: String) -> Bool {
        allowedTargets.contains { target in
            guard case let .application(application) = target else {
                return false
            }
            return application.bundleIdentifier == bundleIdentifier
        }
    }

    private func enforce(
        windows: [CataloguedAccessibilityWindow],
        applicationName: String
    ) throws {
        for window in windows where !windowPolicy.allows(window.observation) {
            try minimize(window, applicationName: applicationName)
        }
    }

    private func minimize(
        _ window: CataloguedAccessibilityWindow,
        applicationName: String
    ) throws {
        switch windowOperator.minimizedState(of: window.element) {
        case .minimized(true), .unavailable:
            return
        case .failed:
            throw ApplicationEnforcementError.windowControlUnavailable(applicationName)
        case .minimized(false):
            break
        }

        switch windowOperator.setMinimized(true, for: window.element) {
        case .success:
            restorationTracker.recordChangedWindow(window.element)
            if let recoveryReference = window.recoveryReference {
                recoveryReferences[recoveryReference.windowIdentifier]
                    = recoveryReference
                do {
                    try persistRecoveryReferences()
                } catch {
                    throw ApplicationEnforcementError.windowRecoveryUnavailable
                }
            }
        case .unavailable:
            return
        case .failed:
            throw ApplicationEnforcementError.windowControlUnavailable(applicationName)
        }
    }

    private func activateInitialAllowedTarget() {
        restoreAllowedFocus(preferredTarget: allowedTargets.first?.id)
    }

    private func restoreAllowedFocus(preferredTarget: TargetIdentifier?) {
        let preferred = preferredTarget.flatMap { identifier in
            allowedTargets.first { $0.id == identifier }
        }
        let orderedTargets = (preferred.map { [$0] } ?? [])
            + allowedTargets.filter { $0.id != preferred?.id }

        for target in orderedTargets where activate(target) {
            return
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func activate(_ target: SessionTarget) -> Bool {
        switch target {
        case let .application(applicationTarget):
            guard let application = runningApplication(for: applicationTarget) else {
                return false
            }
            return application.activate(options: [.activateAllWindows])

        case let .window(windowTarget):
            guard
                let application = runningApplication(for: windowTarget.application),
                let element = windowCatalog.element(for: windowTarget.id)
            else {
                return false
            }
            _ = application.activate(options: [])
            return windowOperator.raise(element) == .success
        }
    }

    private func runningApplication(
        for target: ApplicationTarget
    ) -> NSRunningApplication? {
        let preferredApplication = target.processIdentifier.flatMap {
            NSRunningApplication(processIdentifier: $0)
        }
        if let preferredApplication,
           !preferredApplication.isTerminated,
           preferredApplication.bundleIdentifier == target.bundleIdentifier
        {
            return preferredApplication
        }

        return NSRunningApplication.runningApplications(
            withBundleIdentifier: target.bundleIdentifier
        ).first(where: { !$0.isTerminated })
    }

    private func makeApplicationTarget(
        _ application: NSRunningApplication
    ) -> ApplicationTarget {
        ApplicationTarget(
            displayName: application.localizedName ?? "Application",
            bundleIdentifier: application.bundleIdentifier ?? "",
            processIdentifier: application.processIdentifier,
            applicationURL: application.bundleURL
        )
    }

    private func publishBlockedNotice(_ message: String) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastNoticeUptime >= 2 else {
            return
        }

        lastNoticeUptime = now
        onBlockedApplication?(message)
    }

    private func resolvePersistedRestorationWindows() throws {
        let referencesByProcess = Dictionary(
            grouping: recoveryReferences.values,
            by: {
                RecoveryProcessKey(
                    bundleIdentifier: $0.bundleIdentifier,
                    processIdentifier: $0.processIdentifier
                )
            }
        )
        for (processKey, references) in referencesByProcess {
            guard let runningApplication = NSRunningApplication(
                processIdentifier: processKey.processIdentifier
            ),
            !runningApplication.isTerminated,
            runningApplication.bundleIdentifier == processKey.bundleIdentifier
            else {
                for reference in references {
                    recoveryReferences.removeValue(
                        forKey: reference.windowIdentifier
                    )
                }
                continue
            }

            let application = makeApplicationTarget(runningApplication)
            let windows: [CataloguedAccessibilityWindow]
            do {
                windows = try windowCatalog.catalogueWindows(for: application)
            } catch {
                throw ApplicationEnforcementError.windowRecoveryUnavailable
            }
            for window in windows
                where recoveryReferences[window.target.id] != nil
            {
                restorationTracker.recordChangedWindow(window.element)
            }
            let availableIdentifiers = Set(windows.map(\.target.id))
            for reference in references
                where !availableIdentifiers.contains(reference.windowIdentifier)
            {
                recoveryReferences.removeValue(
                    forKey: reference.windowIdentifier
                )
            }
        }
        try persistRecoveryReferences()
    }

    private func removeResolvedRecoveryReferences() throws {
        for identifier in Array(recoveryReferences.keys) {
            guard let element = windowCatalog.element(for: identifier) else {
                recoveryReferences.removeValue(forKey: identifier)
                continue
            }
            switch windowOperator.minimizedState(of: element) {
            case .minimized(true), .failed:
                continue
            case .minimized(false), .unavailable:
                recoveryReferences.removeValue(forKey: identifier)
            }
        }
        try persistRecoveryReferences()
    }

    private func persistRecoveryReferences() throws {
        try windowRecoveryStore.save(
            recoveryReferences.values.sorted {
                $0.windowIdentifier.rawValue.uuidString
                    < $1.windowIdentifier.rawValue.uuidString
            }
        )
    }
}
