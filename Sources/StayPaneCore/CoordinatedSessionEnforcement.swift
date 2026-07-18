import Foundation

@MainActor
final class CoordinatedSessionEnforcement {
    private enum State {
        case idle
        case awaitingTabConfirmation
        case active
    }

    private let applicationAndWindowEnforcement: any SessionEnforcing
    private let tabActivationEnforcement: any TabActivationEnforcing
    private var state: State = .idle

    init(
        applicationAndWindowEnforcement: any SessionEnforcing,
        tabActivationEnforcement: any TabActivationEnforcing
    ) {
        self.applicationAndWindowEnforcement = applicationAndWindowEnforcement
        self.tabActivationEnforcement = tabActivationEnforcement
    }

    func preflight(targets: [SessionTarget]) throws {
        try tabActivationEnforcement.preflight(
            targets: tabTargets(in: targets)
        )
    }

    func start(allowing targets: [SessionTarget]) throws -> Bool {
        let tabStartResult: TabActivationStartResult
        do {
            tabStartResult = try tabActivationEnforcement.start(
                allowing: tabTargets(in: targets)
            )
        } catch {
            if case .awaitingTabConfirmation = state {
                tabActivationEnforcement.stop()
            }
            state = .idle
            throw error
        }
        guard tabStartResult == .active else {
            state = .awaitingTabConfirmation
            return false
        }
        do {
            try applicationAndWindowEnforcement.start(
                allowing: applicationAndWindowTargets(for: targets)
            )
            state = .active
        } catch {
            tabActivationEnforcement.stop()
            state = .idle
            throw error
        }
        return true
    }

    func resume(allowing targets: [SessionTarget]) throws -> Bool {
        guard try tabActivationEnforcement.resume(
            allowing: tabTargets(in: targets)
        ) == .active else {
            state = .awaitingTabConfirmation
            return false
        }
        do {
            try applicationAndWindowEnforcement.resume(
                allowing: applicationAndWindowTargets(for: targets)
            )
            state = .active
        } catch {
            tabActivationEnforcement.stop()
            state = .idle
            throw error
        }
        return true
    }

    func refresh() throws {
        try applicationAndWindowEnforcement.refresh()
        try tabActivationEnforcement.refresh()
    }

    func stop() {
        switch state {
        case .idle:
            break
        case .awaitingTabConfirmation:
            tabActivationEnforcement.stop()
        case .active:
            applicationAndWindowEnforcement.stop()
            tabActivationEnforcement.stop()
        }
        state = .idle
    }

    func restorePersistedState() {
        applicationAndWindowEnforcement.stop()
        tabActivationEnforcement.stop()
        state = .idle
    }

    private func tabTargets(in targets: [SessionTarget]) -> [BrowserTabTarget] {
        targets.compactMap { target in
            guard case let .browserTab(tab) = target else {
                return nil
            }
            return tab
        }
    }

    private func applicationAndWindowTargets(
        for targets: [SessionTarget]
    ) -> [SessionTarget] {
        var mappedTargets: [SessionTarget] = []
        for target in targets {
            let mappedTarget: SessionTarget
            switch target {
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
