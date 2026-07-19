import Foundation

@MainActor
public protocol BrowserEnforcing: AnyObject {
    func preflight(targets: [BrowserEnforcementTarget]) throws
    func start(allowing targets: [BrowserEnforcementTarget]) throws
        -> BrowserEnforcementStartResult
    func resume(allowing targets: [BrowserEnforcementTarget]) throws
        -> BrowserEnforcementStartResult
    func refresh() throws
    func stop()
}

public extension BrowserEnforcing {
    func resume(
        allowing targets: [BrowserEnforcementTarget]
    ) throws -> BrowserEnforcementStartResult {
        try start(allowing: targets)
    }
}

public enum BrowserEnforcementStartResult: Equatable, Sendable {
    case awaitingAvailability
    case awaitingConfirmation
    case active
}

public enum BrowserEnforcementError: Error, Equatable, Sendable {
    case unavailable
}

@MainActor
public final class UnavailableBrowserEnforcement: BrowserEnforcing {
    public init() {}

    public func preflight(targets: [BrowserEnforcementTarget]) throws {
        if !targets.isEmpty {
            throw BrowserEnforcementError.unavailable
        }
    }

    public func start(
        allowing targets: [BrowserEnforcementTarget]
    ) throws -> BrowserEnforcementStartResult {
        try preflight(targets: targets)
        return .active
    }

    public func refresh() throws {}
    public func stop() {}
}
