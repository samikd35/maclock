import Foundation
import StayPaneBridgeProtocol
import StayPaneCore

enum NativeBridgeError: Error, Equatable {
    case disconnected
    case profileSynchronizing(BrowserProfileIdentifier)
    case unsupportedProfile(BrowserProfileIdentifier)
    case targetMissing
    case startConfirmationTimedOut
    case extensionReported(BridgeEnforcementErrorCode)
}

extension NativeBridgeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .disconnected:
            "The StayPane Chrome extension is disconnected. Connect it before starting a Session with a Browser Window Target or Tab Target."
        case .profileSynchronizing:
            "This Chrome Profile is still synchronizing. Wait for its current windows and tabs before starting."
        case .unsupportedProfile:
            "This Chrome Profile cannot control Incognito windows. Enable Allow in Incognito for the StayPane companion before selecting browser targets."
        case .targetMissing:
            "A selected Chrome window or tab is no longer available. Refresh and choose an open target."
        case .startConfirmationTimedOut:
            "The Chrome extension did not confirm browser enforcement in time."
        case let .extensionReported(code):
            if code == .targetNotReady {
                "Wait for the selected Chrome tab to finish loading, then start the Session again."
            } else {
                "Chrome could not enforce the selected browser target (\(code.rawValue))."
            }
        }
    }
}

enum BrowserProfileAvailability: Equatable {
    case synchronizing
    case ready
    case incognitoWindowControlRequired
}

struct BrowserProfileConnection: Equatable, Identifiable {
    let profileIdentifier: BrowserProfileIdentifier
    let availability: BrowserProfileAvailability

    var id: BrowserProfileIdentifier { profileIdentifier }
}

@MainActor
final class NativeBridgeController: BrowserEnforcing {
    private static let recoveryAvailabilityTimeout: TimeInterval = 5

    private struct BrowserEnforcementPlan: Equatable {
        let configuredTargets: [BrowserEnforcementTarget]
        var availableTargets: [BrowserEnforcementTarget]
        var confirmedProfiles: Set<BrowserProfileIdentifier> = []

        var profileIdentifiers: Set<BrowserProfileIdentifier> {
            Set(configuredTargets.map(\.profileIdentifier))
        }

        func availableWindowIdentifiers(
            for profileIdentifier: BrowserProfileIdentifier
        ) -> Set<Int> {
            Set(availableTargets.compactMap { target in
                guard target.profileIdentifier == profileIdentifier else {
                    return nil
                }
                guard case let .window(window) = target else {
                    return nil
                }
                return window.windowIdentifier.rawValue
            })
        }

        func availableTabIdentifiers(
            for profileIdentifier: BrowserProfileIdentifier
        ) -> Set<Int> {
            Set(availableTargets.compactMap { target in
                guard target.profileIdentifier == profileIdentifier else {
                    return nil
                }
                guard case let .tab(tab) = target else {
                    return nil
                }
                return tab.tabIdentifier.rawValue
            })
        }

        func availableTargets(
            for profileIdentifier: BrowserProfileIdentifier
        ) -> [BrowserEnforcementTarget] {
            availableTargets.filter {
                $0.profileIdentifier == profileIdentifier
            }
        }

        func containsAvailableTab(
            profileIdentifier: BrowserProfileIdentifier,
            tabIdentifier: Int
        ) -> Bool {
            availableTabIdentifiers(for: profileIdentifier).contains(
                tabIdentifier
            )
        }

        mutating func removeAvailableTarget(
            matching identifier: TargetIdentifier
        ) -> BrowserEnforcementTarget? {
            let removedTarget = availableTargets.first(where: {
                $0.targetIdentifier == identifier
            })
            availableTargets.removeAll {
                $0.targetIdentifier == identifier
            }
            return removedTarget
        }
    }

    private enum BrowserEnforcementState {
        case idle
        case awaitingConfirmation(BrowserEnforcementPlan, deadline: Date)
        case active(BrowserEnforcementPlan)

        var plan: BrowserEnforcementPlan? {
            switch self {
            case .idle:
                nil
            case let .awaitingConfirmation(plan, _), let .active(plan):
                plan
            }
        }
    }

    private let listener: LocalBridgeListener
    private let now: () -> Date
    private var pendingConnections: Set<BridgeConnectionIdentifier> = []
    private var profileByConnection: [
        BridgeConnectionIdentifier: BrowserProfileIdentifier
    ] = [:]
    private var connectionByProfile: [
        BrowserProfileIdentifier: BridgeConnectionIdentifier
    ] = [:]
    private var capabilitiesByProfile: [
        BrowserProfileIdentifier: BridgeProfileCapabilities
    ] = [:]
    private var profilesWithSnapshot: Set<BrowserProfileIdentifier> = []
    private var tabsByProfile: [
        BrowserProfileIdentifier: [BridgeTabSnapshot]
    ] = [:]
    private var browserEnforcementState: BrowserEnforcementState = .idle
    private var enforcementFailure: NativeBridgeError?
    private var recoveryAvailabilityDeadline: Date?

    var onChange: (() -> Void)?
    var onBlockedTabActivation: (() -> Void)?
    var onBlockedNavigation: (() -> Void)?
    var onTabTargetClosed: ((TargetIdentifier) -> Void)?
    var onBrowserWindowTargetClosed: ((TargetIdentifier) -> Void)?

    init(
        socketURL: URL = StayPaneBridgeSocketLocation.defaultURL,
        now: @escaping () -> Date = Date.init
    ) throws {
        listener = try LocalBridgeListener(socketURL: socketURL)
        self.now = now
    }

    var isConnected: Bool {
        !connectionByProfile.isEmpty
    }

    var profileConnections: [BrowserProfileConnection] {
        connectionByProfile.keys.map { profileIdentifier in
            BrowserProfileConnection(
                profileIdentifier: profileIdentifier,
                availability: profileAvailability(profileIdentifier)
                    ?? .synchronizing
            )
        }
        .sorted {
            $0.profileIdentifier.rawValue < $1.profileIdentifier.rawValue
        }
    }

    func tabTargets(for application: ApplicationTarget) -> [BrowserTabTarget] {
        tabsByProfile
            .filter { profileAvailability($0.key) == .ready }
            .flatMap { profileIdentifier, tabs in
                tabs.compactMap { tab -> BrowserTabTarget? in
                    guard !tab.isIncognito,
                          let url = Self.eligibleWebURL(from: tab.url)
                    else {
                        return nil
                    }
                    return BrowserTabTarget(
                        profileIdentifier: profileIdentifier,
                        tabIdentifier: BrowserTabIdentifier(
                            rawValue: tab.tabIdentifier
                        ),
                        windowIdentifier: BrowserWindowIdentifier(
                            rawValue: tab.windowIdentifier
                        ),
                        title: tab.title,
                        url: url,
                        faviconPNGData: faviconData(from: tab.faviconDataURL),
                        application: application
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.windowIdentifier != rhs.windowIdentifier {
                    return lhs.windowIdentifier.rawValue
                        < rhs.windowIdentifier.rawValue
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                    == .orderedAscending
            }
    }

    func windowTargets(
        for application: ApplicationTarget
    ) -> [BrowserWindowTarget] {
        tabsByProfile
            .filter { profileAvailability($0.key) == .ready }
            .flatMap { profileIdentifier, tabs in
                Dictionary(
                    grouping: tabs.filter { !$0.isIncognito },
                    by: \.windowIdentifier
                ).map { windowIdentifier, windowTabs in
                    let representative = windowTabs.first(where: \.isActive)
                        ?? windowTabs.first
                    return BrowserWindowTarget(
                        profileIdentifier: profileIdentifier,
                        windowIdentifier: BrowserWindowIdentifier(
                            rawValue: windowIdentifier
                        ),
                        title: representative?.title
                            ?? "Chrome window \(windowIdentifier)",
                        frame: representative?.windowBounds.map {
                            BrowserWindowFrame(
                                x: $0.left,
                                y: $0.top,
                                width: $0.width,
                                height: $0.height
                            )
                        },
                        application: application
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.profileIdentifier != rhs.profileIdentifier {
                    return lhs.profileIdentifier.rawValue
                        < rhs.profileIdentifier.rawValue
                }
                return lhs.windowIdentifier.rawValue
                    < rhs.windowIdentifier.rawValue
            }
    }

    func poll() throws {
        var didChange = false
        for event in try listener.poll() {
            switch event {
            case let .connected(connection):
                pendingConnections.insert(connection)

            case let .message(connection, message):
                didChange = try handle(
                    message,
                    from: connection
                ) || didChange

            case let .rejected(connection):
                didChange = remove(connection: connection) || didChange

            case let .disconnected(connection):
                didChange = remove(connection: connection) || didChange
            }
        }
        if didChange {
            onChange?()
        }
    }

    func preflight(targets: [BrowserEnforcementTarget]) throws {
        try poll()
        _ = try selectedProfiles(for: targets)
        for target in targets {
            try validateAvailable(target)
        }
    }

    func start(
        allowing targets: [BrowserEnforcementTarget]
    ) throws -> BrowserEnforcementStartResult {
        try preflight(targets: targets)
        guard !targets.isEmpty else {
            browserEnforcementState = .idle
            enforcementFailure = nil
            return .active
        }
        if let enforcementFailure {
            throw enforcementFailure
        }
        if let result = try existingStartResult(for: targets) {
            return result
        }
        stop()
        return try beginEnforcement(
            configuredTargets: targets,
            availableTargets: targets
        )
    }

    func resume(
        allowing targets: [BrowserEnforcementTarget]
    ) throws -> BrowserEnforcementStartResult {
        try poll()
        if let enforcementFailure {
            recoveryAvailabilityDeadline = nil
            throw enforcementFailure
        }
        guard !targets.isEmpty else {
            browserEnforcementState = .idle
            recoveryAvailabilityDeadline = nil
            return .active
        }
        if let result = try existingStartResult(for: targets) {
            recoveryAvailabilityDeadline = nil
            return result
        }
        if browserEnforcementState.plan != nil {
            let availabilityDeadline = recoveryAvailabilityDeadline
            stop()
            recoveryAvailabilityDeadline = availabilityDeadline
        }

        let profileIdentifiers = try selectedProfiles(for: targets)
        if let unavailableProfile = profileIdentifiers.first(where: {
            profileAvailability($0) != .ready
        }) {
            return try awaitRecoveryAvailability(
                orThrow: recoveryError(for: unavailableProfile)
            )
        }
        let availableTargets = targets.filter(isAvailable)
        let availableProfiles = Set(
            availableTargets.map(\.profileIdentifier)
        )
        guard !availableTargets.isEmpty,
              availableProfiles == profileIdentifiers
        else {
            return try awaitRecoveryAvailability(orThrow: .targetMissing)
        }

        let result = try beginEnforcement(
            configuredTargets: targets,
            availableTargets: availableTargets
        )
        recoveryAvailabilityDeadline = nil
        return result
    }

    func refresh() throws {
        try poll()
        if let enforcementFailure {
            throw enforcementFailure
        }
    }

    func stop() {
        recoveryAvailabilityDeadline = nil
        guard let plan = browserEnforcementState.plan else {
            enforcementFailure = nil
            return
        }
        for profileIdentifier in plan.profileIdentifiers.sorted(
            by: { $0.rawValue < $1.rawValue }
        ) {
            guard let connection = connectionByProfile[profileIdentifier]
            else {
                continue
            }
            try? listener.send(
                .endEnforcement(profileIdentifier: profileIdentifier.rawValue),
                to: connection
            )
        }
        browserEnforcementState = .idle
        enforcementFailure = nil
    }

    private func handle(
        _ message: BridgeMessage,
        from connection: BridgeConnectionIdentifier
    ) throws -> Bool {
        switch message {
        case let .hello(
            extensionIdentifier,
            profileIdentifier,
            capabilities
        ):
            guard pendingConnections.contains(connection),
                  profileByConnection[connection] == nil,
                  extensionIdentifier
                    == StayPaneBridgeConstants.extensionIdentifier
            else {
                reject(connection)
                return true
            }

            let profile = BrowserProfileIdentifier(rawValue: profileIdentifier)
            if let previous = connectionByProfile[profile],
               previous != connection {
                listener.disconnect(previous)
                _ = remove(connection: previous)
            }
            pendingConnections.remove(connection)
            profileByConnection[connection] = profile
            connectionByProfile[profile] = connection
            capabilitiesByProfile[profile] = capabilities
            profilesWithSnapshot.remove(profile)
            tabsByProfile[profile] = []
            try listener.send(
                .helloAcknowledged(profileIdentifier: profileIdentifier),
                to: connection
            )
            try listener.send(
                .requestTabs(profileIdentifier: profileIdentifier),
                to: connection
            )
            return true

        case let .tabsSnapshot(profileIdentifier, tabs):
            guard let profile = validatedProfile(
                profileIdentifier,
                from: connection
            ) else {
                reject(connection)
                return true
            }
            tabsByProfile[profile] = tabs.filter { !$0.isIncognito }
            profilesWithSnapshot.insert(profile)
            return true

        case let .tabActivated(profileIdentifier, _, _):
            guard validatedProfile(profileIdentifier, from: connection) != nil else {
                reject(connection)
                return true
            }
            return false

        case let .blockedTabActivation(profileIdentifier, _, _):
            guard validatedProfile(profileIdentifier, from: connection) != nil else {
                reject(connection)
                return true
            }
            onBlockedTabActivation?()
            return false

        case let .blockedNavigation(profileIdentifier, tabIdentifier):
            guard let profile = validatedProfile(
                profileIdentifier,
                from: connection
            ) else {
                reject(connection)
                return true
            }
            guard let plan = browserEnforcementState.plan,
                  plan.containsAvailableTab(
                    profileIdentifier: profile,
                    tabIdentifier: tabIdentifier
                  )
            else {
                return false
            }
            onBlockedNavigation?()
            return false

        case let .tabTargetClosed(profileIdentifier, tabIdentifier):
            return handleBrowserTargetClosed(
                profileIdentifier,
                from: connection,
                targetIdentifier: { profile in
                    .browserTab(
                        profileIdentifier: profile,
                        tabIdentifier: BrowserTabIdentifier(
                            rawValue: tabIdentifier
                        )
                    )
                },
                notification: onTabTargetClosed
            )

        case let .browserWindowTargetClosed(
            profileIdentifier,
            windowIdentifier
        ):
            return handleBrowserTargetClosed(
                profileIdentifier,
                from: connection,
                targetIdentifier: { profile in
                    .browserWindow(
                        profileIdentifier: profile,
                        windowIdentifier: BrowserWindowIdentifier(
                            rawValue: windowIdentifier
                        )
                    )
                },
                notification: onBrowserWindowTargetClosed
            )

        case let .enforcementStarted(
            profileIdentifier,
            windowIdentifiers,
            tabIdentifiers
        ):
            guard let profile = validatedProfile(
                profileIdentifier,
                from: connection
            ) else {
                reject(connection)
                return true
            }
            let confirmedWindowIdentifiers = Set(windowIdentifiers)
            let confirmedTabIdentifiers = Set(tabIdentifiers)
            switch browserEnforcementState {
            case let .awaitingConfirmation(currentPlan, deadline)
                where currentPlan.profileIdentifiers.contains(profile)
                    && currentPlan.availableWindowIdentifiers(for: profile)
                        == confirmedWindowIdentifiers
                    && currentPlan.availableTabIdentifiers(for: profile)
                        == confirmedTabIdentifiers:
                var plan = currentPlan
                plan.confirmedProfiles.insert(profile)
                browserEnforcementState = plan.confirmedProfiles
                    == plan.profileIdentifiers
                    ? .active(plan)
                    : .awaitingConfirmation(plan, deadline: deadline)
            case .idle:
                return false
            case let .active(plan)
                where plan.confirmedProfiles.contains(profile)
                    && plan.availableWindowIdentifiers(for: profile)
                        == confirmedWindowIdentifiers
                    && plan.availableTabIdentifiers(for: profile)
                        == confirmedTabIdentifiers:
                return false
            case .awaitingConfirmation, .active:
                reject(connection)
                return true
            }
            return false

        case let .enforcementError(profileIdentifier, code):
            guard let profile = validatedProfile(
                profileIdentifier,
                from: connection
            ) else {
                reject(connection)
                return true
            }
            if browserEnforcementState.plan?.profileIdentifiers
                .contains(profile) == true
            {
                enforcementFailure = .extensionReported(code)
            }
            return false

        case .helloAcknowledged, .requestTabs, .beginEnforcement,
             .endEnforcement:
            reject(connection)
            return true
        }
    }

    private func handleBrowserTargetClosed(
        _ profileIdentifier: String,
        from connection: BridgeConnectionIdentifier,
        targetIdentifier: (BrowserProfileIdentifier) -> TargetIdentifier,
        notification: ((TargetIdentifier) -> Void)?
    ) -> Bool {
        guard let profile = validatedProfile(
            profileIdentifier,
            from: connection
        ) else {
            reject(connection)
            return true
        }
        guard let plan = browserEnforcementState.plan else {
            return false
        }
        guard plan.profileIdentifiers.contains(profile) else {
            reject(connection)
            return true
        }
        let identifier = targetIdentifier(profile)
        var updatedPlan = plan
        let removedTarget = updatedPlan.removeAvailableTarget(
            matching: identifier
        )
        switch browserEnforcementState {
        case let .awaitingConfirmation(_, deadline):
            browserEnforcementState = .awaitingConfirmation(
                updatedPlan,
                deadline: deadline
            )
        case .active:
            browserEnforcementState = .active(updatedPlan)
        case .idle:
            return false
        }
        if removedTarget != nil {
            notification?(identifier)
        }
        return false
    }

    private func existingStartResult(
        for configuredTargets: [BrowserEnforcementTarget]
    ) throws -> BrowserEnforcementStartResult? {
        switch browserEnforcementState {
        case let .active(plan)
            where plan.configuredTargets == configuredTargets:
            return .active
        case let .awaitingConfirmation(plan, deadline)
            where plan.configuredTargets == configuredTargets:
            guard now() < deadline else {
                stop()
                throw NativeBridgeError.startConfirmationTimedOut
            }
            return .awaitingConfirmation
        case .idle, .active, .awaitingConfirmation:
            return nil
        }
    }

    private func beginEnforcement(
        configuredTargets: [BrowserEnforcementTarget],
        availableTargets: [BrowserEnforcementTarget]
    ) throws -> BrowserEnforcementStartResult {
        enforcementFailure = nil
        let plan = BrowserEnforcementPlan(
            configuredTargets: configuredTargets,
            availableTargets: availableTargets
        )
        let deadline = now().addingTimeInterval(2)
        browserEnforcementState = .awaitingConfirmation(
            plan,
            deadline: deadline
        )
        do {
            for profileIdentifier in plan.profileIdentifiers.sorted(
                by: { $0.rawValue < $1.rawValue }
            ) {
                guard let connection = connectionByProfile[profileIdentifier],
                      profileAvailability(profileIdentifier) == .ready
                else {
                    throw NativeBridgeError.disconnected
                }
                let targets = plan.availableTargets(for: profileIdentifier)
                guard !targets.isEmpty else {
                    throw NativeBridgeError.targetMissing
                }
                try listener.send(
                    .beginEnforcement(
                        profileIdentifier: profileIdentifier.rawValue,
                        targets: try targets.map {
                            try bridgeEnforcementTarget(for: $0)
                        }
                    ),
                    to: connection
                )
            }
        } catch {
            stop()
            throw error
        }
        browserEnforcementState = .awaitingConfirmation(
            plan,
            deadline: deadline
        )
        return .awaitingConfirmation
    }

    private func selectedProfiles(
        for targets: [BrowserEnforcementTarget]
    ) throws -> Set<BrowserProfileIdentifier> {
        let profiles = Set(targets.map(\.profileIdentifier))
        guard Set(targets.map(\.targetIdentifier)).count == targets.count
        else {
            throw NativeBridgeError.disconnected
        }
        return profiles
    }

    private func validateAvailable(
        _ target: BrowserEnforcementTarget
    ) throws {
        let profileIdentifier = target.profileIdentifier
        guard connectionByProfile[profileIdentifier] != nil else {
            throw NativeBridgeError.disconnected
        }
        switch profileAvailability(profileIdentifier) {
        case .ready:
            break
        case .synchronizing:
            throw NativeBridgeError.profileSynchronizing(profileIdentifier)
        case .incognitoWindowControlRequired:
            throw NativeBridgeError.unsupportedProfile(profileIdentifier)
        case nil:
            throw NativeBridgeError.disconnected
        }
        if case let .tab(tab) = target {
            guard Self.eligibleWebURL(from: tab.url.absoluteString) != nil else {
                throw NativeBridgeError.targetMissing
            }
        }
        guard isAvailable(target) else {
            throw NativeBridgeError.targetMissing
        }
    }

    private func isAvailable(_ target: BrowserEnforcementTarget) -> Bool {
        switch target {
        case let .window(window):
            tabsByProfile[window.profileIdentifier]?.contains(where: {
                !$0.isIncognito
                    && $0.windowIdentifier
                        == window.windowIdentifier.rawValue
            }) == true
        case let .tab(tab):
            tabsByProfile[tab.profileIdentifier]?.contains(where: {
                !$0.isIncognito
                    && $0.tabIdentifier == tab.tabIdentifier.rawValue
            }) == true
        }
    }

    private func awaitRecoveryAvailability(
        orThrow error: NativeBridgeError
    ) throws -> BrowserEnforcementStartResult {
        let deadline = recoveryAvailabilityDeadline
            ?? now().addingTimeInterval(Self.recoveryAvailabilityTimeout)
        recoveryAvailabilityDeadline = deadline
        guard now() >= deadline else {
            return .awaitingAvailability
        }
        recoveryAvailabilityDeadline = nil
        throw error
    }

    private func profileAvailability(
        _ profileIdentifier: BrowserProfileIdentifier
    ) -> BrowserProfileAvailability? {
        guard connectionByProfile[profileIdentifier] != nil else {
            return nil
        }
        guard capabilitiesByProfile[profileIdentifier]?
            .incognitoWindowControl == true
        else {
            return .incognitoWindowControlRequired
        }
        return profilesWithSnapshot.contains(profileIdentifier)
            ? .ready
            : .synchronizing
    }

    private func recoveryError(
        for profileIdentifier: BrowserProfileIdentifier
    ) -> NativeBridgeError {
        switch profileAvailability(profileIdentifier) {
        case .incognitoWindowControlRequired:
            .unsupportedProfile(profileIdentifier)
        case .synchronizing:
            .profileSynchronizing(profileIdentifier)
        case .ready, nil:
            .disconnected
        }
    }

    private static func eligibleWebURL(from rawValue: String) -> URL? {
        guard let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else {
            return nil
        }
        return url
    }

    private static func bridgeNavigationScope(
        for target: BrowserTabTarget
    ) -> BridgeNavigationScope {
        switch target.navigationScope {
        case .currentWebsite:
            .currentWebsite(initialURL: target.url.absoluteString)
        case .exactPage:
            .exactPage(initialURL: target.url.absoluteString)
        }
    }

    private func bridgeEnforcementTarget(
        for target: BrowserEnforcementTarget
    ) throws -> BridgeEnforcementTarget {
        switch target {
        case let .window(window):
            guard isAvailable(target) else {
                throw NativeBridgeError.targetMissing
            }
            return .window(
                windowIdentifier: window.windowIdentifier.rawValue
            )
        case let .tab(tab):
            guard let liveTab = tabsByProfile[tab.profileIdentifier]?.first(
                where: {
                    !$0.isIncognito
                        && $0.tabIdentifier == tab.tabIdentifier.rawValue
                }
            ) else {
                throw NativeBridgeError.targetMissing
            }
            return .tab(
                tabIdentifier: tab.tabIdentifier.rawValue,
                windowIdentifier: liveTab.windowIdentifier,
                navigationScope: Self.bridgeNavigationScope(for: tab)
            )
        }
    }

    @discardableResult
    private func remove(connection: BridgeConnectionIdentifier) -> Bool {
        pendingConnections.remove(connection)
        guard let profileIdentifier = profileByConnection.removeValue(
            forKey: connection
        ) else {
            return false
        }
        if connectionByProfile[profileIdentifier] == connection {
            connectionByProfile.removeValue(forKey: profileIdentifier)
            capabilitiesByProfile.removeValue(forKey: profileIdentifier)
            profilesWithSnapshot.remove(profileIdentifier)
            tabsByProfile.removeValue(forKey: profileIdentifier)
            if browserEnforcementState.plan?.profileIdentifiers
                .contains(profileIdentifier) == true
            {
                enforcementFailure = .disconnected
            }
        }
        return true
    }

    private func reject(_ connection: BridgeConnectionIdentifier) {
        listener.disconnect(connection)
        _ = remove(connection: connection)
    }

    private func validatedProfile(
        _ rawValue: String,
        from connection: BridgeConnectionIdentifier
    ) -> BrowserProfileIdentifier? {
        let profileIdentifier = BrowserProfileIdentifier(rawValue: rawValue)
        return profileByConnection[connection] == profileIdentifier
            ? profileIdentifier
            : nil
    }

    private func faviconData(from dataURL: String?) -> Data? {
        let prefix = "data:image/png;base64,"
        guard let dataURL, dataURL.hasPrefix(prefix) else {
            return nil
        }
        return Data(base64Encoded: String(dataURL.dropFirst(prefix.count)))
    }
}
