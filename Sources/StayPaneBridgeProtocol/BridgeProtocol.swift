import Foundation

public enum StayPaneBridgeConstants {
    public static let protocolVersion = 1
    public static let nativeHostName = "com.staypane.native_bridge"
    public static let extensionIdentifier = "hoofhoedlagpoclhkgnkmejaihaapoke"
    public static let allowedOrigin = "chrome-extension://\(extensionIdentifier)/"
}

public enum BridgeProtocolError: Error, Equatable, Sendable {
    case invalidJSON
    case invalidSchema
    case unsupportedVersion
    case messageTooLarge
}

public enum BridgeMessageDirection: Equatable, Sendable {
    case extensionToNative
    case nativeToExtension
}

public struct BridgeTabSnapshot: Equatable, Sendable {
    public let tabIdentifier: Int
    public let windowIdentifier: Int
    public let title: String
    public let url: String
    public let faviconDataURL: String?
    public let isActive: Bool
    public let isIncognito: Bool

    public init(
        tabIdentifier: Int,
        windowIdentifier: Int,
        title: String,
        url: String,
        faviconDataURL: String?,
        isActive: Bool,
        isIncognito: Bool
    ) {
        self.tabIdentifier = tabIdentifier
        self.windowIdentifier = windowIdentifier
        self.title = title
        self.url = url
        self.faviconDataURL = faviconDataURL
        self.isActive = isActive
        self.isIncognito = isIncognito
    }
}

public enum BridgeEnforcementErrorCode: String, Equatable, Sendable {
    case targetMissing
    case activationFailed
    case invalidCommand
}

public enum BridgeMessage: Equatable, Sendable {
    case hello(extensionIdentifier: String, profileIdentifier: String)
    case helloAcknowledged(profileIdentifier: String)
    case tabsSnapshot(profileIdentifier: String, tabs: [BridgeTabSnapshot])
    case tabActivated(
        profileIdentifier: String,
        tabIdentifier: Int,
        windowIdentifier: Int
    )
    case blockedTabActivation(
        profileIdentifier: String,
        attemptedTabIdentifier: Int,
        allowedTabIdentifier: Int
    )
    case tabActivationStarted(
        profileIdentifier: String,
        tabIdentifier: Int,
        windowIdentifier: Int
    )
    case enforcementError(
        profileIdentifier: String,
        code: BridgeEnforcementErrorCode
    )
    case requestTabs(profileIdentifier: String)
    case beginEnforcement(
        profileIdentifier: String,
        tabIdentifier: Int,
        windowIdentifier: Int
    )
    case endEnforcement(profileIdentifier: String)

    public var direction: BridgeMessageDirection {
        switch self {
        case .hello, .tabsSnapshot, .tabActivated,
             .blockedTabActivation, .tabActivationStarted,
             .enforcementError:
            .extensionToNative
        case .helloAcknowledged, .requestTabs, .beginEnforcement,
             .endEnforcement:
            .nativeToExtension
        }
    }
}

public enum BridgeMessageCodec {
    public static func decode(_ data: Data) throws -> BridgeMessage {
        guard data.count <= NativeMessageFramer.maximumMessageSize else {
            throw BridgeProtocolError.messageTooLarge
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            throw BridgeProtocolError.invalidJSON
        }
        guard integer(dictionary["version"])
            == StayPaneBridgeConstants.protocolVersion
        else {
            throw BridgeProtocolError.unsupportedVersion
        }
        guard let type = validatedString(dictionary["type"], maximum: 64) else {
            throw BridgeProtocolError.invalidSchema
        }

        switch type {
        case "hello":
            try requireKeys(
                dictionary,
                exactly: ["version", "type", "extensionId", "profileId"]
            )
            guard let extensionIdentifier = validatedString(
                dictionary["extensionId"],
                maximum: 32
            ), extensionIdentifier == StayPaneBridgeConstants.extensionIdentifier,
            let profileIdentifier = profileIdentifier(dictionary["profileId"])
            else {
                throw BridgeProtocolError.invalidSchema
            }
            return .hello(
                extensionIdentifier: extensionIdentifier,
                profileIdentifier: profileIdentifier
            )

        case "helloAck":
            try requireKeys(dictionary, exactly: ["version", "type", "profileId"])
            return .helloAcknowledged(
                profileIdentifier: try requiredProfileIdentifier(dictionary)
            )

        case "tabsSnapshot":
            try requireKeys(
                dictionary,
                exactly: ["version", "type", "profileId", "tabs"]
            )
            guard let rawTabs = dictionary["tabs"] as? [Any],
                  rawTabs.count <= 10_000
            else {
                throw BridgeProtocolError.invalidSchema
            }
            return .tabsSnapshot(
                profileIdentifier: try requiredProfileIdentifier(dictionary),
                tabs: try rawTabs.map(decodeTab)
            )

        case "tabActivated":
            try requireKeys(
                dictionary,
                exactly: ["version", "type", "profileId", "tabId", "windowId"]
            )
            return .tabActivated(
                profileIdentifier: try requiredProfileIdentifier(dictionary),
                tabIdentifier: try requiredPositiveInteger(
                    dictionary,
                    key: "tabId"
                ),
                windowIdentifier: try requiredPositiveInteger(
                    dictionary,
                    key: "windowId"
                )
            )

        case "blockedTabActivation":
            try requireKeys(
                dictionary,
                exactly: [
                    "version", "type", "profileId", "attemptedTabId",
                    "allowedTabId"
                ]
            )
            return .blockedTabActivation(
                profileIdentifier: try requiredProfileIdentifier(dictionary),
                attemptedTabIdentifier: try requiredPositiveInteger(
                    dictionary,
                    key: "attemptedTabId"
                ),
                allowedTabIdentifier: try requiredPositiveInteger(
                    dictionary,
                    key: "allowedTabId"
                )
            )

        case "tabActivationStarted":
            try requireKeys(
                dictionary,
                exactly: ["version", "type", "profileId", "tabId", "windowId"]
            )
            return .tabActivationStarted(
                profileIdentifier: try requiredProfileIdentifier(dictionary),
                tabIdentifier: try requiredPositiveInteger(
                    dictionary,
                    key: "tabId"
                ),
                windowIdentifier: try requiredPositiveInteger(
                    dictionary,
                    key: "windowId"
                )
            )

        case "enforcementError":
            try requireKeys(
                dictionary,
                exactly: ["version", "type", "profileId", "code"]
            )
            guard let rawCode = validatedString(dictionary["code"], maximum: 64),
                  let code = BridgeEnforcementErrorCode(rawValue: rawCode)
            else {
                throw BridgeProtocolError.invalidSchema
            }
            return .enforcementError(
                profileIdentifier: try requiredProfileIdentifier(dictionary),
                code: code
            )

        case "requestTabs":
            try requireKeys(dictionary, exactly: ["version", "type", "profileId"])
            return .requestTabs(
                profileIdentifier: try requiredProfileIdentifier(dictionary)
            )

        case "beginEnforcement":
            try requireKeys(
                dictionary,
                exactly: ["version", "type", "profileId", "tabId", "windowId"]
            )
            return .beginEnforcement(
                profileIdentifier: try requiredProfileIdentifier(dictionary),
                tabIdentifier: try requiredPositiveInteger(
                    dictionary,
                    key: "tabId"
                ),
                windowIdentifier: try requiredPositiveInteger(
                    dictionary,
                    key: "windowId"
                )
            )

        case "endEnforcement":
            try requireKeys(dictionary, exactly: ["version", "type", "profileId"])
            return .endEnforcement(
                profileIdentifier: try requiredProfileIdentifier(dictionary)
            )

        default:
            throw BridgeProtocolError.invalidSchema
        }
    }

    public static func encode(_ message: BridgeMessage) throws -> Data {
        var object: [String: Any] = [
            "version": StayPaneBridgeConstants.protocolVersion
        ]
        switch message {
        case let .hello(extensionIdentifier, profileIdentifier):
            object.merge([
                "type": "hello",
                "extensionId": extensionIdentifier,
                "profileId": profileIdentifier
            ]) { _, new in new }
        case let .helloAcknowledged(profileIdentifier):
            object.merge([
                "type": "helloAck",
                "profileId": profileIdentifier
            ]) { _, new in new }
        case let .tabsSnapshot(profileIdentifier, tabs):
            object.merge([
                "type": "tabsSnapshot",
                "profileId": profileIdentifier,
                "tabs": tabs.map(encodeTab)
            ]) { _, new in new }
        case let .tabActivated(profileIdentifier, tabIdentifier, windowIdentifier):
            object.merge([
                "type": "tabActivated",
                "profileId": profileIdentifier,
                "tabId": tabIdentifier,
                "windowId": windowIdentifier
            ]) { _, new in new }
        case let .blockedTabActivation(
            profileIdentifier,
            attemptedTabIdentifier,
            allowedTabIdentifier
        ):
            object.merge([
                "type": "blockedTabActivation",
                "profileId": profileIdentifier,
                "attemptedTabId": attemptedTabIdentifier,
                "allowedTabId": allowedTabIdentifier
            ]) { _, new in new }
        case let .tabActivationStarted(
            profileIdentifier,
            tabIdentifier,
            windowIdentifier
        ):
            object.merge([
                "type": "tabActivationStarted",
                "profileId": profileIdentifier,
                "tabId": tabIdentifier,
                "windowId": windowIdentifier
            ]) { _, new in new }
        case let .enforcementError(profileIdentifier, code):
            object.merge([
                "type": "enforcementError",
                "profileId": profileIdentifier,
                "code": code.rawValue
            ]) { _, new in new }
        case let .requestTabs(profileIdentifier):
            object.merge([
                "type": "requestTabs",
                "profileId": profileIdentifier
            ]) { _, new in new }
        case let .beginEnforcement(
            profileIdentifier,
            tabIdentifier,
            windowIdentifier
        ):
            object.merge([
                "type": "beginEnforcement",
                "profileId": profileIdentifier,
                "tabId": tabIdentifier,
                "windowId": windowIdentifier
            ]) { _, new in new }
        case let .endEnforcement(profileIdentifier):
            object.merge([
                "type": "endEnforcement",
                "profileId": profileIdentifier
            ]) { _, new in new }
        }
        guard JSONSerialization.isValidJSONObject(object) else {
            throw BridgeProtocolError.invalidSchema
        }
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        _ = try decode(data)
        return data
    }

    private static func decodeTab(_ value: Any) throws -> BridgeTabSnapshot {
        guard let dictionary = value as? [String: Any] else {
            throw BridgeProtocolError.invalidSchema
        }
        let requiredKeys: Set<String> = [
            "tabId", "windowId", "title", "url", "active", "incognito"
        ]
        let allowedKeys = requiredKeys.union(["faviconDataUrl"])
        guard requiredKeys.isSubset(of: dictionary.keys),
              Set(dictionary.keys).isSubset(of: allowedKeys),
              let title = validatedString(dictionary["title"], maximum: 2_048),
              let url = validatedString(dictionary["url"], maximum: 8_192),
              URL(string: url) != nil,
              let isActive = dictionary["active"] as? Bool,
              let isIncognito = dictionary["incognito"] as? Bool
        else {
            throw BridgeProtocolError.invalidSchema
        }
        let faviconDataURL: String?
        if let rawFavicon = dictionary["faviconDataUrl"] {
            guard let favicon = validatedString(rawFavicon, maximum: 65_536),
                  validatedPNGData(from: favicon) != nil
            else {
                throw BridgeProtocolError.invalidSchema
            }
            faviconDataURL = favicon
        } else {
            faviconDataURL = nil
        }
        return BridgeTabSnapshot(
            tabIdentifier: try requiredPositiveInteger(dictionary, key: "tabId"),
            windowIdentifier: try requiredPositiveInteger(
                dictionary,
                key: "windowId"
            ),
            title: title,
            url: url,
            faviconDataURL: faviconDataURL,
            isActive: isActive,
            isIncognito: isIncognito
        )
    }

    private static func encodeTab(_ tab: BridgeTabSnapshot) -> [String: Any] {
        var object: [String: Any] = [
            "tabId": tab.tabIdentifier,
            "windowId": tab.windowIdentifier,
            "title": tab.title,
            "url": tab.url,
            "active": tab.isActive,
            "incognito": tab.isIncognito
        ]
        if let faviconDataURL = tab.faviconDataURL {
            object["faviconDataUrl"] = faviconDataURL
        }
        return object
    }

    private static func validatedPNGData(from dataURL: String) -> Data? {
        let prefix = "data:image/png;base64,"
        guard dataURL.hasPrefix(prefix),
              let data = Data(
                base64Encoded: String(dataURL.dropFirst(prefix.count))
              ),
              data.starts(with: [
                0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
              ])
        else {
            return nil
        }
        return data
    }

    private static func requireKeys(
        _ dictionary: [String: Any],
        exactly keys: Set<String>
    ) throws {
        guard Set(dictionary.keys) == keys else {
            throw BridgeProtocolError.invalidSchema
        }
    }

    private static func requiredProfileIdentifier(
        _ dictionary: [String: Any]
    ) throws -> String {
        guard let value = profileIdentifier(dictionary["profileId"]) else {
            throw BridgeProtocolError.invalidSchema
        }
        return value
    }

    private static func profileIdentifier(_ value: Any?) -> String? {
        guard let value = validatedString(value, maximum: 128),
              value.range(
                of: #"^[A-Za-z0-9_-]+$"#,
                options: .regularExpression
              ) != nil
        else {
            return nil
        }
        return value
    }

    private static func requiredPositiveInteger(
        _ dictionary: [String: Any],
        key: String
    ) throws -> Int {
        guard let value = integer(dictionary[key]), value >= 0 else {
            throw BridgeProtocolError.invalidSchema
        }
        return value
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              String(cString: number.objCType) != "c"
        else {
            return nil
        }
        let double = number.doubleValue
        guard double.rounded() == double,
              double >= Double(Int.min),
              double <= Double(Int.max)
        else {
            return nil
        }
        return number.intValue
    }

    private static func validatedString(
        _ value: Any?,
        maximum: Int
    ) -> String? {
        guard let value = value as? String,
              !value.isEmpty,
              value.utf8.count <= maximum
        else {
            return nil
        }
        return value
    }
}

public enum NativeHostOriginValidator {
    public static func isAllowed(_ origin: String) -> Bool {
        origin == StayPaneBridgeConstants.allowedOrigin
    }
}

public enum NativeMessageFramer {
    public static let maximumMessageSize = 1_048_576

    public static func frame(_ payload: Data) throws -> Data {
        guard !payload.isEmpty,
              payload.count <= maximumMessageSize,
              let length = UInt32(exactly: payload.count)
        else {
            throw BridgeProtocolError.messageTooLarge
        }
        var littleEndianLength = length.littleEndian
        var framed = withUnsafeBytes(of: &littleEndianLength) { Data($0) }
        framed.append(payload)
        return framed
    }

    public static func extractMessages(
        from buffer: inout Data
    ) throws -> [Data] {
        var messages: [Data] = []
        while buffer.count >= 4 {
            let length = Int(buffer.prefix(4).enumerated().reduce(UInt32(0)) {
                partial, element in
                partial | (UInt32(element.element) << UInt32(element.offset * 8))
            })
            guard length > 0, length <= maximumMessageSize else {
                throw BridgeProtocolError.messageTooLarge
            }
            guard buffer.count >= 4 + length else {
                break
            }
            messages.append(buffer.subdata(in: 4..<(4 + length)))
            buffer.removeSubrange(0..<(4 + length))
        }
        return messages
    }
}
