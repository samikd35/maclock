import Foundation

@MainActor
final class CoordinatedSessionEnforcement {
    private enum State {
        case idle
        case awaitingBrowserEnforcement
        case active
    }

    private let applicationAndWindowEnforcement: any SessionEnforcing
    private let browserEnforcement: any BrowserEnforcing
    private var state: State = .idle

    init(
        applicationAndWindowEnforcement: any SessionEnforcing,
        browserEnforcement: any BrowserEnforcing
    ) {
        self.applicationAndWindowEnforcement = applicationAndWindowEnforcement
        self.browserEnforcement = browserEnforcement
    }

    func preflight(targets: [SessionTarget]) throws {
        try browserEnforcement.preflight(
            targets: browserTargets(in: targets)
        )
    }

    func start(
        allowing targets: [SessionTarget]
    ) throws -> CoordinatedSessionEnforcementResult {
        let browserStartResult: BrowserEnforcementStartResult
        do {
            browserStartResult = try browserEnforcement.start(
                allowing: browserTargets(in: targets)
            )
        } catch {
            if case .awaitingBrowserEnforcement = state {
                browserEnforcement.stop()
            }
            state = .idle
            throw error
        }
        guard browserStartResult == .active else {
            state = .awaitingBrowserEnforcement
            return .awaitingBrowserEnforcement
        }
        do {
            try applicationAndWindowEnforcement.start(
                allowing: applicationAndWindowTargets(for: targets)
            )
            state = .active
        } catch {
            browserEnforcement.stop()
            state = .idle
            throw error
        }
        return .active
    }

    func resume(
        allowing targets: [SessionTarget]
    ) throws -> CoordinatedSessionEnforcementResult {
        guard try browserEnforcement.resume(
            allowing: browserTargets(in: targets)
        ) == .active else {
            state = .awaitingBrowserEnforcement
            return .awaitingBrowserEnforcement
        }
        do {
            try applicationAndWindowEnforcement.resume(
                allowing: applicationAndWindowTargets(for: targets)
            )
            state = .active
        } catch {
            browserEnforcement.stop()
            state = .idle
            throw error
        }
        return .active
    }

    func refresh() throws {
        try applicationAndWindowEnforcement.refresh()
        try browserEnforcement.refresh()
    }

    func stop() {
        switch state {
        case .idle:
            break
        case .awaitingBrowserEnforcement:
            browserEnforcement.stop()
        case .active:
            applicationAndWindowEnforcement.stop()
            browserEnforcement.stop()
        }
        state = .idle
    }

    func restorePersistedState() {
        applicationAndWindowEnforcement.stop()
        browserEnforcement.stop()
        state = .idle
    }

    private func browserTargets(
        in targets: [SessionTarget]
    ) -> [BrowserEnforcementTarget] {
        targets.compactMap { target in
            switch target {
            case let .browserWindow(window):
                return .window(window)
            case let .browserTab(tab):
                return .tab(tab)
            case .application, .window:
                return nil
            }
        }
    }

    private func applicationAndWindowTargets(
        for targets: [SessionTarget]
    ) -> [SessionTarget] {
        var mappedTargets: [SessionTarget] = []
        for target in targets {
            let mappedTarget: SessionTarget
            switch target {
            case let .browserWindow(window):
                mappedTarget = .application(window.application)
            case let .browserTab(tab):
                mappedTarget = .application(tab.application)
            case .application, .window:
                mappedTarget = target
            }
            if !mappedTargets.contains(where: { $0.id == mappedTarget.id }) {
                mappedTargets.append(mappedTarget)
            }
        }
        return mappedTargets
    }
}

enum CoordinatedSessionEnforcementResult: Equatable {
    case awaitingBrowserEnforcement
    case active
}
