import Foundation
import StayPaneBridgeProtocol
import StayPaneCore

enum BrowserBridgeError: Error, Equatable {
    case disconnected
    case targetMissing
    case multipleTabTargetsUnsupported
    case extensionReported(BridgeEnforcementErrorCode)
}

extension BrowserBridgeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .disconnected:
            "The StayPane Chrome extension is disconnected. Connect it before starting a tab session."
        case .targetMissing:
            "The selected Chrome tab is no longer available. Refresh and choose an open tab."
        case .multipleTabTargetsUnsupported:
            "This version of StayPane supports one Chrome tab per session."
        case let .extensionReported(code):
            "Chrome could not enforce the selected tab (\(code.rawValue))."
        }
    }
}

@MainActor
final class BrowserBridgeController: BrowserSessionEnforcing {
    private let server: LocalBridgeServer
    private var pendingConnections: Set<BridgeConnectionIdentifier> = []
    private var profileByConnection: [BridgeConnectionIdentifier: String] = [:]
    private var connectionByProfile: [String: BridgeConnectionIdentifier] = [:]
    private var tabsByProfile: [String: [BridgeTabSnapshot]] = [:]
    private var enforcedTarget: BrowserTabTarget?
    private var enforcementFailure: BrowserBridgeError?

    var onChange: (() -> Void)?
    var onBlockedTabActivation: (() -> Void)?

    init(
        socketURL: URL = StayPaneBridgeSocketLocation.defaultURL
    ) throws {
        server = try LocalBridgeServer(socketURL: socketURL)
    }

    var isConnected: Bool {
        !connectionByProfile.isEmpty
    }

    var connectedProfileCount: Int {
        connectionByProfile.count
    }

    func targets(for application: ApplicationTarget) -> [BrowserTabTarget] {
        tabsByProfile
            .flatMap { profileIdentifier, tabs in
                tabs.compactMap { tab -> BrowserTabTarget? in
                    guard !tab.isIncognito,
                          let url = URL(string: tab.url)
                    else {
                        return nil
                    }
                    return BrowserTabTarget(
                        profileIdentifier: BrowserProfileIdentifier(
                            rawValue: profileIdentifier
                        ),
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
        for event in try server.poll() {
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
            throw BrowserBridgeError.multipleTabTargetsUnsupported
        }
        for target in targets {
            try validateAvailable(target)
        }
    }

    func start(allowing targets: [BrowserTabTarget]) throws {
        try preflight(targets: targets)
        guard let target = targets.first else {
            enforcedTarget = nil
            enforcementFailure = nil
            return
        }
        let profileIdentifier = target.profileIdentifier.rawValue
        guard let connection = connectionByProfile[profileIdentifier] else {
            throw BrowserBridgeError.disconnected
        }
        try server.send(
            .beginEnforcement(
                profileIdentifier: profileIdentifier,
                tabIdentifier: target.tabIdentifier.rawValue,
                windowIdentifier: target.windowIdentifier.rawValue
            ),
            to: connection
        )
        enforcedTarget = target
        enforcementFailure = nil
    }

    func refresh() throws {
        try poll()
        if let enforcementFailure {
            throw enforcementFailure
        }
        if let enforcedTarget {
            try validateAvailable(enforcedTarget)
        }
    }

    func stop() {
        guard let target = enforcedTarget else {
            enforcementFailure = nil
            return
        }
        let profileIdentifier = target.profileIdentifier.rawValue
        if let connection = connectionByProfile[profileIdentifier] {
            try? server.send(
                .endEnforcement(profileIdentifier: profileIdentifier),
                to: connection
            )
        }
        enforcedTarget = nil
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

            if let previous = connectionByProfile[profileIdentifier],
               previous != connection {
                server.disconnect(previous)
                _ = remove(connection: previous)
            }
            pendingConnections.remove(connection)
            profileByConnection[connection] = profileIdentifier
            connectionByProfile[profileIdentifier] = connection
            tabsByProfile[profileIdentifier] = []
            try server.send(
                .helloAcknowledged(profileIdentifier: profileIdentifier),
                to: connection
            )
            try server.send(
                .requestTabs(profileIdentifier: profileIdentifier),
                to: connection
            )
            return true

        case let .tabsSnapshot(profileIdentifier, tabs):
            guard profileByConnection[connection] == profileIdentifier else {
                reject(connection)
                return true
            }
            tabsByProfile[profileIdentifier] = tabs.filter { !$0.isIncognito }
            return true

        case let .tabActivated(profileIdentifier, _, _):
            guard profileByConnection[connection] == profileIdentifier else {
                reject(connection)
                return true
            }
            return false

        case let .blockedTabActivation(profileIdentifier, _, _):
            guard profileByConnection[connection] == profileIdentifier else {
                reject(connection)
                return true
            }
            onBlockedTabActivation?()
            return false

        case let .enforcementError(profileIdentifier, code):
            guard profileByConnection[connection] == profileIdentifier else {
                reject(connection)
                return true
            }
            if enforcedTarget?.profileIdentifier.rawValue == profileIdentifier {
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
        let profileIdentifier = target.profileIdentifier.rawValue
        guard connectionByProfile[profileIdentifier] != nil else {
            throw BrowserBridgeError.disconnected
        }
        guard tabsByProfile[profileIdentifier]?.contains(where: {
            !$0.isIncognito
                && $0.tabIdentifier == target.tabIdentifier.rawValue
                && $0.windowIdentifier == target.windowIdentifier.rawValue
        }) == true else {
            throw BrowserBridgeError.targetMissing
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
            tabsByProfile.removeValue(forKey: profileIdentifier)
            if enforcedTarget?.profileIdentifier.rawValue == profileIdentifier {
                enforcementFailure = .disconnected
            }
        }
        return true
    }

    private func reject(_ connection: BridgeConnectionIdentifier) {
        server.disconnect(connection)
        _ = remove(connection: connection)
    }

    private func faviconData(from dataURL: String?) -> Data? {
        let prefix = "data:image/png;base64,"
        guard let dataURL, dataURL.hasPrefix(prefix) else {
            return nil
        }
        return Data(base64Encoded: String(dataURL.dropFirst(prefix.count)))
    }
}
