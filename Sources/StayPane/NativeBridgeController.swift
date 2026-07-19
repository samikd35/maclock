import Foundation
import StayPaneBridgeProtocol
import StayPaneCore

enum NativeBridgeError: Error, Equatable {
    case disconnected
    case targetMissing
    case multipleTabTargetsUnsupported
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
        case .multipleTabTargetsUnsupported:
            "This version of StayPane supports one Chrome Tab Target per Session."
        case .startConfirmationTimedOut:
            "The Chrome extension did not confirm Tab Activation Enforcement in time."
        case let .extensionReported(code):
            "Chrome could not enforce the selected tab (\(code.rawValue))."
        }
    }
}

@MainActor
final class NativeBridgeController: TabActivationEnforcing {
    private static let recoveryAvailabilityTimeout: TimeInterval = 5

    private enum TabActivationState {
        case idle
        case awaitingConfirmation(BrowserTabTarget, deadline: Date)
        case active(BrowserTabTarget)

        var target: BrowserTabTarget? {
            switch self {
            case .idle:
                nil
            case let .awaitingConfirmation(target, _), let .active(target):
                target
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
        guard targets.count <= 1 else {
            throw NativeBridgeError.multipleTabTargetsUnsupported
        }
        for target in targets {
            try validateAvailable(target)
        }
    }

    func start(
        allowing targets: [BrowserTabTarget]
    ) throws -> TabActivationStartResult {
        try preflight(targets: targets)
        guard let target = targets.first else {
            tabActivationState = .idle
            enforcementFailure = nil
            return .active
        }
        if let enforcementFailure {
            throw enforcementFailure
        }
        switch tabActivationState {
        case let .active(activeTarget)
            where activeTarget.targetIdentifier == target.targetIdentifier:
            return .active
        case let .awaitingConfirmation(pendingTarget, deadline)
            where pendingTarget.targetIdentifier == target.targetIdentifier:
            guard now() < deadline else {
                stop()
                throw NativeBridgeError.startConfirmationTimedOut
            }
            return .awaitingConfirmation
        case .idle, .active, .awaitingConfirmation:
            stop()
        }

        let profileIdentifier = target.profileIdentifier
        guard let connection = connectionByProfile[profileIdentifier] else {
            throw NativeBridgeError.disconnected
        }
        enforcementFailure = nil
        try listener.send(
            .beginEnforcement(
                profileIdentifier: profileIdentifier.rawValue,
                tabIdentifier: target.tabIdentifier.rawValue,
                windowIdentifier: target.windowIdentifier.rawValue,
                navigationScope: .currentWebsite(
                    initialURL: target.url.absoluteString
                )
            ),
            to: connection
        )
        tabActivationState = .awaitingConfirmation(
            target,
            deadline: now().addingTimeInterval(2)
        )
        return .awaitingConfirmation
    }

    func resume(
        allowing targets: [BrowserTabTarget]
    ) throws -> TabActivationStartResult {
        do {
            let result = try start(allowing: targets)
            recoveryAvailabilityDeadline = nil
            return result
        } catch let error as NativeBridgeError {
            guard error == .disconnected || error == .targetMissing else {
                recoveryAvailabilityDeadline = nil
                throw error
            }
            let deadline = recoveryAvailabilityDeadline
                ?? now().addingTimeInterval(Self.recoveryAvailabilityTimeout)
            recoveryAvailabilityDeadline = deadline
            guard now() >= deadline else {
                return .awaitingAvailability
            }
            recoveryAvailabilityDeadline = nil
            throw error
        }
    }

    func refresh() throws {
        try poll()
        if let enforcementFailure {
            throw enforcementFailure
        }
        if let target = tabActivationState.target {
            try validateAvailable(target)
        }
    }

    func stop() {
        recoveryAvailabilityDeadline = nil
        guard let target = tabActivationState.target else {
            enforcementFailure = nil
            return
        }
        let profileIdentifier = target.profileIdentifier
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
            tabsByProfile[profile] = tabs.filter {
                !$0.isIncognito && Self.eligibleWebURL(from: $0.url) != nil
            }
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
            guard let target = tabActivationState.target,
                  target.profileIdentifier == profile,
                  target.tabIdentifier.rawValue == tabIdentifier
            else {
                return false
            }
            onBlockedNavigation?()
            return false

        case let .tabActivationStarted(
            profileIdentifier,
            tabIdentifier,
            windowIdentifier
        ):
            guard let profile = validatedProfile(
                profileIdentifier,
                from: connection
            ) else {
                reject(connection)
                return true
            }
            switch tabActivationState {
            case let .awaitingConfirmation(target, _)
                where target.profileIdentifier == profile
                    && target.tabIdentifier.rawValue == tabIdentifier
                    && target.windowIdentifier.rawValue == windowIdentifier:
                tabActivationState = .active(target)
            case .idle:
                return false
            case let .active(target)
                where target.profileIdentifier == profile
                    && target.tabIdentifier.rawValue == tabIdentifier
                    && target.windowIdentifier.rawValue == windowIdentifier:
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
            if tabActivationState.target?.profileIdentifier == profile {
                enforcementFailure = .extensionReported(code)
            }
            return false

        case .helloAcknowledged, .requestTabs, .beginEnforcement,
             .endEnforcement:
            reject(connection)
            return true
        }
    }

    private func validateAvailable(_ target: BrowserTabTarget) throws {
        let profileIdentifier = target.profileIdentifier
        guard connectionByProfile[profileIdentifier] != nil else {
            throw NativeBridgeError.disconnected
        }
        guard tabsByProfile[profileIdentifier]?.contains(where: {
            !$0.isIncognito
                && Self.eligibleWebURL(from: $0.url) != nil
                && $0.tabIdentifier == target.tabIdentifier.rawValue
                && $0.windowIdentifier == target.windowIdentifier.rawValue
        }) == true else {
            throw NativeBridgeError.targetMissing
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
            if tabActivationState.target?.profileIdentifier == profileIdentifier {
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
