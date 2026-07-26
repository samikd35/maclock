import Foundation

public struct NativeMessagingHostManifest: Codable, Equatable, Sendable {
    public let name: String
    public let description: String
    public let path: String
    public let type: String
    public let allowedOrigins: [String]

    public init(
        name: String,
        description: String,
        path: String,
        type: String,
        allowedOrigins: [String]
    ) {
        self.name = name
        self.description = description
        self.path = path
        self.type = type
        self.allowedOrigins = allowedOrigins
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case path
        case type
        case allowedOrigins = "allowed_origins"
    }
}

public enum NativeMessagingHostInstallerError: Error, Equatable, Sendable {
    case hostExecutableMissing
}

public enum NativeMessagingHostRegistrationStatus: Equatable, Sendable {
    case missingOrInvalid
    case installed
    case pointsElsewhere(URL)
}

extension NativeMessagingHostInstallerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .hostExecutableMissing:
            "The packaged StayPaneBridge executable is missing. Build StayPane before registering Chrome."
        }
    }
}

public struct NativeMessagingHostInstaller: Sendable {
    public let manifestDirectoryURL: URL

    public init(
        manifestDirectoryURL: URL = Self.defaultManifestDirectoryURL
    ) {
        self.manifestDirectoryURL = manifestDirectoryURL
    }

    @discardableResult
    public func install(hostExecutableURL: URL) throws -> URL {
        guard FileManager.default.isExecutableFile(
            atPath: hostExecutableURL.path
        ) else {
            throw NativeMessagingHostInstallerError.hostExecutableMissing
        }
        try FileManager.default.createDirectory(
            at: manifestDirectoryURL,
            withIntermediateDirectories: true
        )
        let manifestURL = manifestDirectoryURL.appendingPathComponent(
            "\(StayPaneBridgeConstants.nativeHostName).json",
            isDirectory: false
        )
        let manifest = NativeMessagingHostManifest(
            name: StayPaneBridgeConstants.nativeHostName,
            description: "StayPane Native Bridge",
            path: hostExecutableURL.standardizedFileURL.path,
            type: "stdio",
            allowedOrigins: [StayPaneBridgeConstants.allowedOrigin]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: manifestURL.path
        )
        return manifestURL
    }

    public func isInstalled(hostExecutableURL: URL) -> Bool {
        registrationStatus(hostExecutableURL: hostExecutableURL) == .installed
    }

    public func registrationStatus(
        hostExecutableURL: URL
    ) -> NativeMessagingHostRegistrationStatus {
        let manifestURL = manifestDirectoryURL.appendingPathComponent(
            "\(StayPaneBridgeConstants.nativeHostName).json",
            isDirectory: false
        )
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(
                NativeMessagingHostManifest.self,
                from: data
              )
        else {
            return .missingOrInvalid
        }
        guard manifest.name == StayPaneBridgeConstants.nativeHostName,
              manifest.type == "stdio",
              manifest.allowedOrigins == [StayPaneBridgeConstants.allowedOrigin]
        else {
            return .missingOrInvalid
        }

        let registeredExecutableURL = URL(
            fileURLWithPath: manifest.path
        ).standardizedFileURL
        return registeredExecutableURL == hostExecutableURL.standardizedFileURL
            ? .installed
            : .pointsElsewhere(registeredExecutableURL)
    }

    public static var defaultManifestDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Google", isDirectory: true)
            .appendingPathComponent("Chrome", isDirectory: true)
            .appendingPathComponent("NativeMessagingHosts", isDirectory: true)
    }
}
