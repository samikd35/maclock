import Foundation

public struct BrowserProfileIdentifier: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct BrowserTabIdentifier: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public struct BrowserWindowIdentifier: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public enum BrowserNavigationScope: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case currentWebsite
    case exactPage
}

public struct BrowserWindowFrame: Codable, Equatable, Hashable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct BrowserWindowTarget: Codable, Equatable, Hashable, Sendable {
    public let profileIdentifier: BrowserProfileIdentifier
    public let windowIdentifier: BrowserWindowIdentifier
    public let title: String
    public let frame: BrowserWindowFrame?
    public let application: ApplicationTarget

    public init(
        profileIdentifier: BrowserProfileIdentifier,
        windowIdentifier: BrowserWindowIdentifier,
        title: String = "Chrome window",
        frame: BrowserWindowFrame? = nil,
        application: ApplicationTarget
    ) {
        self.profileIdentifier = profileIdentifier
        self.windowIdentifier = windowIdentifier
        self.title = title
        self.frame = frame
        self.application = application
    }

    public var targetIdentifier: TargetIdentifier {
        .browserWindow(
            profileIdentifier: profileIdentifier,
            windowIdentifier: windowIdentifier
        )
    }

    private enum CodingKeys: String, CodingKey {
        case profileIdentifier
        case windowIdentifier
        case title
        case frame
        case application
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileIdentifier = try container.decode(
            BrowserProfileIdentifier.self,
            forKey: .profileIdentifier
        )
        windowIdentifier = try container.decode(
            BrowserWindowIdentifier.self,
            forKey: .windowIdentifier
        )
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? "Chrome window \(windowIdentifier.rawValue)"
        frame = try container.decodeIfPresent(
            BrowserWindowFrame.self,
            forKey: .frame
        )
        application = try container.decode(
            ApplicationTarget.self,
            forKey: .application
        )
    }
}

public struct BrowserTabTarget: Codable, Equatable, Hashable, Sendable {
    public let profileIdentifier: BrowserProfileIdentifier
    public let tabIdentifier: BrowserTabIdentifier
    public let windowIdentifier: BrowserWindowIdentifier
    public let title: String
    public let url: URL
    public let faviconPNGData: Data?
    public let application: ApplicationTarget
    public let navigationScope: BrowserNavigationScope

    public init(
        profileIdentifier: BrowserProfileIdentifier,
        tabIdentifier: BrowserTabIdentifier,
        windowIdentifier: BrowserWindowIdentifier,
        title: String,
        url: URL,
        faviconPNGData: Data?,
        application: ApplicationTarget,
        navigationScope: BrowserNavigationScope = .currentWebsite
    ) {
        self.profileIdentifier = profileIdentifier
        self.tabIdentifier = tabIdentifier
        self.windowIdentifier = windowIdentifier
        self.title = title
        self.url = url
        self.faviconPNGData = faviconPNGData
        self.application = application
        self.navigationScope = navigationScope
    }

    public var targetIdentifier: TargetIdentifier {
        .browserTab(
            profileIdentifier: profileIdentifier,
            tabIdentifier: tabIdentifier
        )
    }

    private enum CodingKeys: String, CodingKey {
        case profileIdentifier
        case tabIdentifier
        case windowIdentifier
        case title
        case url
        case faviconPNGData
        case application
        case navigationScope
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileIdentifier = try container.decode(
            BrowserProfileIdentifier.self,
            forKey: .profileIdentifier
        )
        tabIdentifier = try container.decode(
            BrowserTabIdentifier.self,
            forKey: .tabIdentifier
        )
        windowIdentifier = try container.decode(
            BrowserWindowIdentifier.self,
            forKey: .windowIdentifier
        )
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(URL.self, forKey: .url)
        faviconPNGData = try container.decodeIfPresent(
            Data.self,
            forKey: .faviconPNGData
        )
        application = try container.decode(
            ApplicationTarget.self,
            forKey: .application
        )
        navigationScope = try container.decodeIfPresent(
            BrowserNavigationScope.self,
            forKey: .navigationScope
        ) ?? .currentWebsite
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profileIdentifier, forKey: .profileIdentifier)
        try container.encode(tabIdentifier, forKey: .tabIdentifier)
        try container.encode(windowIdentifier, forKey: .windowIdentifier)
        try container.encode(title, forKey: .title)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(
            faviconPNGData,
            forKey: .faviconPNGData
        )
        try container.encode(application, forKey: .application)
        try container.encode(navigationScope, forKey: .navigationScope)
    }
}

public enum BrowserEnforcementTarget: Equatable, Hashable, Sendable {
    case window(BrowserWindowTarget)
    case tab(BrowserTabTarget)

    public var profileIdentifier: BrowserProfileIdentifier {
        switch self {
        case let .window(window):
            window.profileIdentifier
        case let .tab(tab):
            tab.profileIdentifier
        }
    }

    public var targetIdentifier: TargetIdentifier {
        switch self {
        case let .window(window):
            window.targetIdentifier
        case let .tab(tab):
            tab.targetIdentifier
        }
    }
}
