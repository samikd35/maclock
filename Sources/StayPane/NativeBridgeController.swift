import Foundation
import StayPaneBridgeProtocol
import StayPaneCore

enum NativeBridgeError: Error, Equatable {
    case disconnected
    case targetMissing
    case startConfirmationTimedOut
    case extensionReported(BridgeEnforcementErrorCode)
}

extension NativeBridgeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .disconnected:
            "The StayPane Chrome extension is disconnected. Connect it before starting a Session with a Tab Target."
        case .targetMissing:
            "The selected Chrome tab is no longer available. Refresh and choose an open tab."
        case .startConfirmationTimedOut:
            "The Chrome extension did not confirm Tab Activation Enforcement in time."
        case let .extensionReported(code):
            if code == .targetNotReady {
                "Wait for the selected Chrome tab to finish loading, then start the Session again."
            } else {
                "Chrome could not enforce the selected tab (\(code.rawValue))."
            }
        }
    }
}

@MainActor
final class NativeBridgeController: TabActivationEnforcing {
    private static let recoveryAvailabilityTimeout: TimeInterval = 5

    private struct TabActivationPlan: Equatable {
        let configuredTargets: [BrowserTabTarget]
        var availableTargets: [BrowserTabTarget]

        var profileIdentifier: BrowserProfileIdentifier? {
            configuredTargets.first?.profileIdentifier
        }

        mutating func removeAvailableTarget(
            tabIdentifier: Int
        ) -> BrowserTabTarget? {
            let removedTarget = availableTargets.first(where: {
                $0.tabIdentifier.rawValue == tabIdentifier
            })
            availableTargets.removeAll {
                $0.tabIdentifier.rawValue == tabIdentifier
            }
            return removedTarget
        }
    }

    private enum TabActivationState {
        case idle
        case awaitingConfirmation(TabActivationPlan, deadline: Date)
        case active(TabActivationPlan)

        var plan: TabActivationPlan? {
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
    private var tabsByProfile: [
        BrowserProfileIdentifier: [BridgeTabSnapshot]
    ] = [:]
    private var tabActivationState: TabActivationState = .idle
    private var enforcementFailure: NativeBridgeError?
    private var recoveryAvailabilityDeadline: Date?

    var onChange: (() -> Void)?
    var onBlockedTabActivation: (() -> Void)?
    var onBlockedNavigation: (() -> Void)?
    var onTabTargetClosed: ((TargetIdentifier) -> Void)?

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

    func targets(for application: ApplicationTarget) -> [BrowserTabTarget] {
        tabsByProfile
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

    func preflight(targets: [BrowserTabTarget]) throws {
        try poll()
        _ = try selectedProfile(for: targets)
        for target in targets {
            try validateAvailable(target)
        }
    }

    func start(
        allowing targets: [BrowserTabTarget]
    ) throws -> TabActivationStartResult {
        try preflight(targets: targets)
        guard !targets.isEmpty else {
            tabActivationState = .idle
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

        let profileIdentifier = targets[0].profileIdentifier
        guard let connection = connectionByProfile[profileIdentifier] else {
            throw NativeBridgeError.disconnected
        }
        return try beginEnforcement(
            configuredTargets: targets,
            availableTargets: targets,
            profileIdentifier: profileIdentifier,
            connection: connection
        )
    }

    func resume(
        allowing targets: [BrowserTabTarget]
    ) throws -> TabActivationStartResult {
        try poll()
        if let enforcementFailure {
            recoveryAvailabilityDeadline = nil
            throw enforcementFailure
        }
        guard !targets.isEmpty else {
            tabActivationState = .idle
            recoveryAvailabilityDeadline = nil
            return .active
        }
        if let result = try existingStartResult(for: targets) {
            recoveryAvailabilityDeadline = nil
            return result
        }
        if tabActivationState.plan != nil {
            let availabilityDeadline = recoveryAvailabilityDeadline
            stop()
            recoveryAvailabilityDeadline = availabilityDeadline
        }

        guard let profileIdentifier = try selectedProfile(for: targets),
              let connection = connectionByProfile[profileIdentifier]
        else {
            return try awaitRecoveryAvailability(orThrow: .disconnected)
        }
        let availableTargets = targets.filter(isAvailable)
        guard !availableTargets.isEmpty else {
            return try awaitRecoveryAvailability(orThrow: .targetMissing)
        }

        let result = try beginEnforcement(
            configuredTargets: targets,
            availableTargets: availableTargets,
            profileIdentifier: profileIdentifier,
            connection: connection
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
        guard let plan = tabActivationState.plan,
              let profileIdentifier = plan.profileIdentifier
        else {
            enforcementFailure = nil
            return
        }
        if let connection = connectionByProfile[profileIdentifier] {
            try? listener.send(
                .endEnforcement(profileIdentifier: profileIdentifier.rawValue),
                to: connection
            )
        }
        tabActivationState = .idle
        enforcementFailure = nil
    }

    private func handle(
        _ message: BridgeMessage,
        from connection: BridgeConnectionIdentifier
    ) throws -> Bool {
        switch message {
        case let .hello(extensionIdentifier, profileIdentifier):
            guard pendingConnections.contains(connection),
                  profileByConnection[connection] == nil,
                  extensionIdentifier
                    == StayPaneBridgeConstants.extensionIdentifier
            else {
                reject(connection)
                return true
            }

            let profile = BrowserProfileIdentifier(rawValue: profileIdentifier)
            if let connectedProfile = connectionByProfile.keys.first,
               connectedProfile != profile {
                reject(connection)
                return true
            }

            if let previous = connectionByProfile[profile],
               previous != connection {
                listener.disconnect(previous)
                _ = remove(connection: previous)
            }
            pendingConnections.remove(connection)
            profileByConnection[connection] = profile
            connectionByProfile[profile] = connection
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
            guard let plan = tabActivationState.plan,
                  plan.profileIdentifier == profile,
                  plan.availableTargets.contains(where: {
                      $0.tabIdentifier.rawValue == tabIdentifier
                  })
            else {
                return false
            }
            onBlockedNavigation?()
            return false

        case let .tabTargetClosed(profileIdentifier, tabIdentifier):
            guard let profile = validatedProfile(
                profileIdentifier,
                from: connection
            ) else {
                reject(connection)
                return true
            }
            guard let plan = tabActivationState.plan else {
                return false
            }
            guard plan.profileIdentifier == profile else {
                reject(connection)
                return true
            }
            var updatedPlan = plan
            let removedTarget = updatedPlan.removeAvailableTarget(
                tabIdentifier: tabIdentifier
            )
            switch tabActivationState {
            case let .awaitingConfirmation(_, deadline):
                tabActivationState = .awaitingConfirmation(
                    updatedPlan,
                    deadline: deadline
                )
            case .active:
                tabActivationState = .active(updatedPlan)
            case .idle:
                return false
            }
            if let removedTarget {
                onTabTargetClosed?(removedTarget.targetIdentifier)
            }
            return false

        case let .enforcementStarted(profileIdentifier, tabIdentifiers):
            guard let profile = validatedProfile(
                profileIdentifier,
                from: connection
            ) else {
                reject(connection)
                return true
            }
            let confirmedIdentifiers = Set(tabIdentifiers)
            switch tabActivationState {
            case let .awaitingConfirmation(plan, _)
                where plan.profileIdentifier == profile
                    && Set(plan.availableTargets.map {
                        $0.tabIdentifier.rawValue
                    }) == confirmedIdentifiers:
                tabActivationState = .active(plan)
            case .idle:
                return false
            case let .active(plan)
                where plan.profileIdentifier == profile
                    && Set(plan.availableTargets.map {
                        $0.tabIdentifier.rawValue
                    }) == confirmedIdentifiers:
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
            if tabActivationState.plan?.profileIdentifier == profile {
                enforcementFailure = .extensionReported(code)
            }
            return false

        case .helloAcknowledged, .requestTabs, .beginEnforcement,
             .endEnforcement:
            reject(connection)
            return true
        }
    }

    private func existingStartResult(
        for configuredTargets: [BrowserTabTarget]
    ) throws -> TabActivationStartResult? {
        switch tabActivationState {
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
        configuredTargets: [BrowserTabTarget],
        availableTargets: [BrowserTabTarget],
        profileIdentifier: BrowserProfileIdentifier,
        connection: BridgeConnectionIdentifier
    ) throws -> TabActivationStartResult {
        enforcementFailure = nil
        try listener.send(
            .beginEnforcement(
                profileIdentifier: profileIdentifier.rawValue,
                targets: try availableTargets.map {
                    try bridgeEnforcementTarget(for: $0)
                }
            ),
            to: connection
        )
        tabActivationState = .awaitingConfirmation(
            TabActivationPlan(
                configuredTargets: configuredTargets,
                availableTargets: availableTargets
            ),
            deadline: now().addingTimeInterval(2)
        )
        return .awaitingConfirmation
    }

    private func selectedProfile(
        for targets: [BrowserTabTarget]
    ) throws -> BrowserProfileIdentifier? {
        let profiles = Set(targets.map(\.profileIdentifier))
        guard profiles.count <= 1,
              Set(targets.map(\.targetIdentifier)).count == targets.count
        else {
            throw NativeBridgeError.disconnected
        }
        return profiles.first
    }

    private func validateAvailable(_ target: BrowserTabTarget) throws {
        let profileIdentifier = target.profileIdentifier
        guard connectionByProfile[profileIdentifier] != nil else {
            throw NativeBridgeError.disconnected
        }
        guard Self.eligibleWebURL(
            from: target.url.absoluteString
        ) != nil else {
            throw NativeBridgeError.targetMissing
        }
        guard isAvailable(target) else {
            throw NativeBridgeError.targetMissing
        }
    }

    private func isAvailable(_ target: BrowserTabTarget) -> Bool {
        tabsByProfile[target.profileIdentifier]?.contains(where: {
            !$0.isIncognito
                && $0.tabIdentifier == target.tabIdentifier.rawValue
        }) == true
    }

    private func awaitRecoveryAvailability(
        orThrow error: NativeBridgeError
    ) throws -> TabActivationStartResult {
        let deadline = recoveryAvailabilityDeadline
            ?? now().addingTimeInterval(Self.recoveryAvailabilityTimeout)
        recoveryAvailabilityDeadline = deadline
        guard now() >= deadline else {
            return .awaitingAvailability
        }
        recoveryAvailabilityDeadline = nil
        throw error
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
        for target: BrowserTabTarget
    ) throws -> BridgeEnforcementTarget {
        guard let liveTab = tabsByProfile[target.profileIdentifier]?.first(
            where: {
                !$0.isIncognito
                    && $0.tabIdentifier == target.tabIdentifier.rawValue
            }
        ) else {
            throw NativeBridgeError.targetMissing
        }
        return BridgeEnforcementTarget(
            tabIdentifier: target.tabIdentifier.rawValue,
            windowIdentifier: liveTab.windowIdentifier,
            navigationScope: Self.bridgeNavigationScope(for: target)
        )
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
            tabsByProfile.removeValue(forKey: profileIdentifier)
            if tabActivationState.plan?.profileIdentifier == profileIdentifier {
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
