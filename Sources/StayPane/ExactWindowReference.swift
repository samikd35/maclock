import Foundation
import StayPaneCore

enum PersistentWindowIdentity: Equatable, Hashable, Sendable {
    case accessibilityIdentifier(String)
    case coreGraphicsWindowNumber(UInt32)
}

struct ExactWindowReference: Codable, Equatable, Hashable, Sendable {
    let windowIdentifier: WindowIdentifier
    let bundleIdentifier: String
    let processIdentifier: Int32
    let identity: PersistentWindowIdentity

    var accessibilityIdentifier: String? {
        guard case let .accessibilityIdentifier(identifier) = identity else {
            return nil
        }
        return identifier
    }

    var coreGraphicsWindowNumber: UInt32? {
        guard case let .coreGraphicsWindowNumber(windowNumber) = identity else {
            return nil
        }
        return windowNumber
    }

    init(
        windowIdentifier: WindowIdentifier,
        bundleIdentifier: String,
        processIdentifier: Int32,
        accessibilityIdentifier: String
    ) {
        self.windowIdentifier = windowIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        identity = .accessibilityIdentifier(accessibilityIdentifier)
    }

    init(
        windowIdentifier: WindowIdentifier,
        bundleIdentifier: String,
        processIdentifier: Int32,
        coreGraphicsWindowNumber: UInt32
    ) {
        self.windowIdentifier = windowIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        identity = .coreGraphicsWindowNumber(coreGraphicsWindowNumber)
    }

    private enum CodingKeys: String, CodingKey {
        case windowIdentifier
        case bundleIdentifier
        case processIdentifier
        case accessibilityIdentifier
        case coreGraphicsWindowNumber
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowIdentifier = try container.decode(
            WindowIdentifier.self,
            forKey: .windowIdentifier
        )
        bundleIdentifier = try container.decode(
            String.self,
            forKey: .bundleIdentifier
        )
        processIdentifier = try container.decode(
            Int32.self,
            forKey: .processIdentifier
        )
        let accessibilityIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .accessibilityIdentifier
        )
        let coreGraphicsWindowNumber = try container.decodeIfPresent(
            UInt32.self,
            forKey: .coreGraphicsWindowNumber
        )
        switch (accessibilityIdentifier, coreGraphicsWindowNumber) {
        case let (.some(identifier), .none):
            identity = .accessibilityIdentifier(identifier)
        case let (.none, .some(windowNumber)):
            identity = .coreGraphicsWindowNumber(windowNumber)
        case (.none, .none), (.some, .some):
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "An exact window reference must contain exactly one persistent identity."
                )
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(windowIdentifier, forKey: .windowIdentifier)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(processIdentifier, forKey: .processIdentifier)
        switch identity {
        case let .accessibilityIdentifier(identifier):
            try container.encode(identifier, forKey: .accessibilityIdentifier)
        case let .coreGraphicsWindowNumber(windowNumber):
            try container.encode(windowNumber, forKey: .coreGraphicsWindowNumber)
        }
    }
}
