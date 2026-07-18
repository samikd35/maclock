import Foundation

@MainActor
public protocol BrowserSessionEnforcing: AnyObject {
    func preflight(targets: [BrowserTabTarget]) throws
    func start(allowing targets: [BrowserTabTarget]) throws
    func resume(allowing targets: [BrowserTabTarget]) throws
    func refresh() throws
    func stop()
}

public extension BrowserSessionEnforcing {
    func resume(allowing targets: [BrowserTabTarget]) throws {
        try start(allowing: targets)
    }
}

public enum BrowserSessionEnforcementError: Error, Equatable, Sendable {
    case unavailable
}

@MainActor
public final class UnavailableBrowserSessionEnforcement: BrowserSessionEnforcing {
    public init() {}

    public func preflight(targets: [BrowserTabTarget]) throws {
        if !targets.isEmpty {
            throw BrowserSessionEnforcementError.unavailable
        }
    }

    public func start(allowing targets: [BrowserTabTarget]) throws {
        try preflight(targets: targets)
    }

    public func refresh() throws {}
    public func stop() {}
}
