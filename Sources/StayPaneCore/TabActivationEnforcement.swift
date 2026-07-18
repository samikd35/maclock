import Foundation

@MainActor
public protocol TabActivationEnforcing: AnyObject {
    func preflight(targets: [BrowserTabTarget]) throws
    func start(allowing targets: [BrowserTabTarget]) throws
        -> TabActivationStartResult
    func resume(allowing targets: [BrowserTabTarget]) throws
        -> TabActivationStartResult
    func refresh() throws
    func stop()
}

public extension TabActivationEnforcing {
    func resume(
        allowing targets: [BrowserTabTarget]
    ) throws -> TabActivationStartResult {
        try start(allowing: targets)
    }
}

public enum TabActivationStartResult: Equatable, Sendable {
    case awaitingConfirmation
    case active
}

public enum TabActivationEnforcementError: Error, Equatable, Sendable {
    case unavailable
}

@MainActor
public final class UnavailableTabActivationEnforcement: TabActivationEnforcing {
    public init() {}

    public func preflight(targets: [BrowserTabTarget]) throws {
        if !targets.isEmpty {
            throw TabActivationEnforcementError.unavailable
        }
    }

    public func start(
        allowing targets: [BrowserTabTarget]
    ) throws -> TabActivationStartResult {
        try preflight(targets: targets)
        return .active
    }

    public func refresh() throws {}
    public func stop() {}
}
