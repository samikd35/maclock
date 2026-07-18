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

public struct BrowserTabTarget: Codable, Equatable, Hashable, Sendable {
    public let profileIdentifier: BrowserProfileIdentifier
    public let tabIdentifier: BrowserTabIdentifier
    public let windowIdentifier: BrowserWindowIdentifier
    public let title: String
    public let url: URL
    public let faviconPNGData: Data?
    public let application: ApplicationTarget

    public init(
        profileIdentifier: BrowserProfileIdentifier,
        tabIdentifier: BrowserTabIdentifier,
        windowIdentifier: BrowserWindowIdentifier,
        title: String,
        url: URL,
        faviconPNGData: Data?,
        application: ApplicationTarget
    ) {
        self.profileIdentifier = profileIdentifier
        self.tabIdentifier = tabIdentifier
        self.windowIdentifier = windowIdentifier
        self.title = title
        self.url = url
        self.faviconPNGData = faviconPNGData
        self.application = application
    }

    public var targetIdentifier: TargetIdentifier {
        .browserTab(
            profileIdentifier: profileIdentifier,
            tabIdentifier: tabIdentifier
        )
    }
}
