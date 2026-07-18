import Foundation
import Testing
@testable import StayPane

@MainActor
@Test func launchAtLoginDefaultsToEnabledForRestartRecovery() {
    let defaults = launchAtLoginTestDefaults()
    defer {
        defaults.removePersistentDomain(
            forName: defaultsSuiteName(defaults)
        )
    }
    let controller = FakeLaunchAtLoginController(status: .disabled)

    let model = LaunchAtLoginModel(
        defaults: defaults,
        controller: controller
    )

    #expect(model.isEnabled)
    #expect(model.isEffective)
    #expect(controller.requestedValues == [true])
    #expect(model.recoveryLimitation == nil)
}

@MainActor
@Test func disablingLaunchAtLoginExplainsTheRecoveryLimitation() {
    let defaults = launchAtLoginTestDefaults()
    defer {
        defaults.removePersistentDomain(
            forName: defaultsSuiteName(defaults)
        )
    }
    let controller = FakeLaunchAtLoginController(status: .enabled)
    let model = LaunchAtLoginModel(
        defaults: defaults,
        controller: controller
    )

    model.setEnabled(false)

    #expect(!model.isEnabled)
    #expect(!model.isEffective)
    #expect(controller.requestedValues == [false])
    #expect(
        model.recoveryLimitation
            == "StayPane cannot automatically resume an unfinished Session after login while Launch at Login is disabled."
    )
}

@MainActor
@Test func aStoredEnabledPreferenceRetriesMissingRegistration() {
    let defaults = launchAtLoginTestDefaults()
    defer {
        defaults.removePersistentDomain(
            forName: defaultsSuiteName(defaults)
        )
    }
    defaults.set(true, forKey: LaunchAtLoginModel.preferenceKey)
    let controller = FakeLaunchAtLoginController(status: .disabled)

    let model = LaunchAtLoginModel(
        defaults: defaults,
        controller: controller
    )

    #expect(model.isEnabled)
    #expect(model.isEffective)
    #expect(controller.requestedValues == [true])
}

@MainActor
private final class FakeLaunchAtLoginController: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus
    var requestedValues: [Bool] = []

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func setEnabled(_ enabled: Bool) throws {
        requestedValues.append(enabled)
        status = enabled ? .enabled : .disabled
    }

    func openSystemSettings() {}
}

private func launchAtLoginTestDefaults() -> UserDefaults {
    let suiteName = UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.set(suiteName, forKey: "testSuiteName")
    defaults.removeObject(forKey: LaunchAtLoginModel.preferenceKey)
    return defaults
}

private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
    defaults.string(forKey: "testSuiteName")!
}
