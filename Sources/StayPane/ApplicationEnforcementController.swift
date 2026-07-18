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
    case exactWindowIdentityUnavailable([String])
    case windowRestorationUnavailable(String)
    case windowEnforcementPersistenceUnavailable

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
        case let .exactWindowIdentityUnavailable(windowTitles):
            "These Window Targets do not expose a stable Exact Window Identity: \(windowTitles.joined(separator: ", ")). Choose their Application Targets instead."
        case let .windowRestorationUnavailable(windowTitle):
            "StayPane cannot persist the Exact Window Identity required for Restoration of \(windowTitle), so reliable enforcement cannot continue."
        case .windowEnforcementPersistenceUnavailable:
            "StayPane could not load or save the exact-window enforcement state required for reliable Recovery and Restoration."
        }
    }
}

@MainActor
final class ApplicationEnforcementController: NSObject, SessionEnforcing {
    private struct ProcessKey: Hashable {
        let bundleIdentifier: String
        let processIdentifier: Int32
    }

    var onBlockedApplication: ((String) -> Void)?
    var onEnforcementFailure: ((Error) -> Void)?
    var onRestorationFailure: ((Int) -> Void)?
    var onRestorationRecovered: (() -> Void)?

    var pendingRestorationCount: Int {
        max(restorationTracker.pendingCount, restorationReferences.count)
    }

    private let permissionClient: any AccessibilityPermissionChecking
    private let availabilityResolver: any ApplicationAvailabilityResolving
    private let windowCatalog: AccessibilityWindowCatalog
    private let notificationCenter: NotificationCenter
    private let windowOperator: any AccessibilityWindowOperating
    private let restorationTracker: WindowRestorationTracker
    private let windowEnforcementStore: any WindowEnforcementPersisting
    private let workspaceApplications: any WorkspaceApplicationAccessing
    private var allowedTargets: [SessionTarget] = []
    private var windowPolicy = WindowAllowlistPolicy(targets: [])
    private var isObserving = false
    private var lastNoticeUptime: TimeInterval = -.infinity
    private var lastFullScanUptime: TimeInterval = -.infinity
    private var allowedWindowReferences: [WindowIdentifier: ExactWindowReference]
    private var restorationReferences: [WindowIdentifier: ExactWindowReference]
    private var windowEnforcementLoadFailed = false

    private static let fullScanInterval: TimeInterval = 0.25

    init(
        permissionClient: any AccessibilityPermissionChecking,
        availabilityResolver: any ApplicationAvailabilityResolving,
        windowCatalog: AccessibilityWindowCatalog = AccessibilityWindowCatalog(),
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        windowOperator: any AccessibilityWindowOperating = SystemAccessibilityWindowOperator(),
        windowEnforcementStore: any WindowEnforcementPersisting = FileWindowEnforcementStore(),
        workspaceApplications: any WorkspaceApplicationAccessing = SystemWorkspaceApplicationAccess()
    ) {
        self.permissionClient = permissionClient
        self.availabilityResolver = availabilityResolver
        self.windowCatalog = windowCatalog
        self.notificationCenter = notificationCenter
        self.windowOperator = windowOperator
        self.windowEnforcementStore = windowEnforcementStore
        self.workspaceApplications = workspaceApplications
        restorationTracker = WindowRestorationTracker(operatorClient: windowOperator)
        let loadedSnapshot: WindowEnforcementSnapshot
        do {
            loadedSnapshot = try windowEnforcementStore.load()
                ?? WindowEnforcementSnapshot(
                    allowedWindowReferences: [],
                    restorationReferences: []
                )
        } catch {
            loadedSnapshot = WindowEnforcementSnapshot(
                allowedWindowReferences: [],
                restorationReferences: []
            )
            windowEnforcementLoadFailed = true
        }
        allowedWindowReferences = [:]
        for reference in loadedSnapshot.allowedWindowReferences {
            allowedWindowReferences[reference.windowIdentifier] = reference
        }
        restorationReferences = [:]
        for reference in loadedSnapshot.restorationReferences {
            restorationReferences[reference.windowIdentifier] = reference
        }
        windowCatalog.registerExactWindowReferences(
            loadedSnapshot.allowedWindowReferences
                + loadedSnapshot.restorationReferences
        )
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
        guard !windowEnforcementLoadFailed else {
            throw ApplicationEnforcementError.windowEnforcementPersistenceUnavailable
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
        try resolvePersistedWindowReferences()
        if !isRecovery, pendingRestorationCount > 0 {
            let outcome = restorationTracker.restorePendingWindows()
            try removeResolvedRestorationReferences()
            guard outcome.pendingCount == 0 else {
                throw ApplicationEnforcementError.windowRestorationPending(
                    outcome.pendingCount
                )
            }
        }
        if !isRecovery {
            allowedWindowReferences = try exactWindowReferences(for: targets)
            try persistWindowEnforcementSnapshot()
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
            try resolvePersistedWindowReferences()
            allowedWindowReferences.removeAll()
            let outcome = restorationTracker.restorePendingWindows()
            try removeResolvedRestorationReferences()
            if outcome.pendingCount > 0 || !restorationReferences.isEmpty {
                onRestorationFailure?(pendingRestorationCount)
            }
        } catch {
            allowedWindowReferences.removeAll()
            try? persistWindowEnforcementSnapshot()
            onRestorationFailure?(pendingRestorationCount)
        }
    }

    func retryPendingRestorations() {
        guard allowedTargets.isEmpty, pendingRestorationCount > 0 else {
            return
        }

        do {
            try resolvePersistedWindowReferences()
            let outcome = restorationTracker.restorePendingWindows()
            try removeResolvedRestorationReferences()
            if outcome.pendingCount == 0, restorationReferences.isEmpty {
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
        let frontmostProcessIdentifier = workspaceApplications.frontmostApplication?
            .processIdentifier
        var refocusTarget: TargetIdentifier?
        var blockedNotice: String?

        for application in workspaceApplications.runningApplications where
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

        guard let exactReference = window.exactReference else {
            throw ApplicationEnforcementError.windowRestorationUnavailable(
                window.target.title
            )
        }
        restorationReferences[exactReference.windowIdentifier] = exactReference
        do {
            try persistWindowEnforcementSnapshot()
        } catch {
            restorationReferences.removeValue(
                forKey: exactReference.windowIdentifier
            )
            throw ApplicationEnforcementError.windowEnforcementPersistenceUnavailable
        }

        switch windowOperator.setMinimized(true, for: window.element) {
        case .success:
            restorationTracker.recordChangedWindow(window.element)
        case .unavailable:
            try discardRestorationReference(exactReference.windowIdentifier)
            return
        case .failed:
            try discardRestorationReference(exactReference.windowIdentifier)
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

        case let .browserTab(tabTarget):
            guard let application = runningApplication(
                for: tabTarget.application
            ) else {
                return false
            }
            return application.activate(options: [.activateAllWindows])
        }
    }

    private func runningApplication(
        for target: ApplicationTarget
    ) -> NSRunningApplication? {
        let preferredApplication = target.processIdentifier.flatMap {
            workspaceApplications.application(processIdentifier: $0)
        }
        if let preferredApplication,
           !preferredApplication.isTerminated,
           preferredApplication.bundleIdentifier == target.bundleIdentifier
        {
            return preferredApplication
        }

        return workspaceApplications.runningApplications(
            bundleIdentifier: target.bundleIdentifier
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

    private func exactWindowReferences(
        for targets: [SessionTarget]
    ) throws -> [WindowIdentifier: ExactWindowReference] {
        let windowTargets = targets.compactMap { target -> WindowTarget? in
            guard case let .window(window) = target else {
                return nil
            }
            return window
        }
        var references: [WindowIdentifier: ExactWindowReference] = [:]
        var unavailableTitles: [String] = []
        var unstableTitles: [String] = []

        for windowTarget in windowTargets {
            let windows: [CataloguedAccessibilityWindow]
            do {
                windows = try windowCatalog.catalogueWindows(
                    for: windowTarget.application
                )
            } catch {
                unavailableTitles.append(windowTarget.title)
                continue
            }
            guard let window = windows.first(where: {
                $0.target.id == windowTarget.id
            }) else {
                unavailableTitles.append(windowTarget.title)
                continue
            }
            guard let exactReference = window.exactReference else {
                unstableTitles.append(windowTarget.title)
                continue
            }
            references[windowTarget.id] = exactReference
        }

        guard unavailableTitles.isEmpty else {
            throw ApplicationEnforcementError.allowedWindowsUnavailable(
                unavailableTitles
            )
        }
        guard unstableTitles.isEmpty else {
            throw ApplicationEnforcementError.exactWindowIdentityUnavailable(
                unstableTitles
            )
        }
        return references
    }

    private func resolvePersistedWindowReferences() throws {
        let allReferences = Array(allowedWindowReferences.values)
            + Array(restorationReferences.values)
        let referencesByProcess = Dictionary(
            grouping: allReferences,
            by: {
                ProcessKey(
                    bundleIdentifier: $0.bundleIdentifier,
                    processIdentifier: $0.processIdentifier
                )
            }
        )
        for (processKey, references) in referencesByProcess {
            guard let runningApplication = workspaceApplications.application(
                processIdentifier: processKey.processIdentifier
            ),
            !runningApplication.isTerminated,
            runningApplication.bundleIdentifier == processKey.bundleIdentifier
            else {
                for reference in references {
                    allowedWindowReferences.removeValue(
                        forKey: reference.windowIdentifier
                    )
                    restorationReferences.removeValue(
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
                throw ApplicationEnforcementError.windowEnforcementPersistenceUnavailable
            }
            for window in windows
                where restorationReferences[window.target.id] != nil
            {
                restorationTracker.recordChangedWindow(window.element)
            }
            let availableIdentifiers = Set(windows.map(\.target.id))
            for reference in references
                where !availableIdentifiers.contains(reference.windowIdentifier)
            {
                allowedWindowReferences.removeValue(
                    forKey: reference.windowIdentifier
                )
                restorationReferences.removeValue(
                    forKey: reference.windowIdentifier
                )
            }
        }
        try persistWindowEnforcementSnapshot()
    }

    private func removeResolvedRestorationReferences() throws {
        for identifier in Array(restorationReferences.keys) {
            guard let element = windowCatalog.element(for: identifier) else {
                restorationReferences.removeValue(forKey: identifier)
                continue
            }
            switch windowOperator.minimizedState(of: element) {
            case .minimized(true), .failed:
                continue
            case .minimized(false), .unavailable:
                restorationReferences.removeValue(forKey: identifier)
            }
        }
        try persistWindowEnforcementSnapshot()
    }

    private func discardRestorationReference(
        _ identifier: WindowIdentifier
    ) throws {
        restorationReferences.removeValue(forKey: identifier)
        do {
            try persistWindowEnforcementSnapshot()
        } catch {
            throw ApplicationEnforcementError.windowEnforcementPersistenceUnavailable
        }
    }

    private func persistWindowEnforcementSnapshot() throws {
        try windowEnforcementStore.save(
            WindowEnforcementSnapshot(
                allowedWindowReferences: sortedExactWindowReferences(
                    Array(allowedWindowReferences.values)
                ),
                restorationReferences: sortedExactWindowReferences(
                    Array(restorationReferences.values)
                )
            )
        )
        windowEnforcementLoadFailed = false
    }

    private func sortedExactWindowReferences(
        _ references: [ExactWindowReference]
    ) -> [ExactWindowReference] {
        references.sorted {
            $0.windowIdentifier.rawValue.uuidString
                < $1.windowIdentifier.rawValue.uuidString
        }
    }
}
