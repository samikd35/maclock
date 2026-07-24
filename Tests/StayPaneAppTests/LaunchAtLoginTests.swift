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
    #expect(model.presentation.statusTitle == "Active")
}

@MainActor
@Test func unavailableLaunchAtLoginNeverLooksEnabled() {
    let defaults = launchAtLoginTestDefaults()
    defer {
        defaults.removePersistentDomain(
            forName: defaultsSuiteName(defaults)
        )
    }
    defaults.set(true, forKey: LaunchAtLoginModel.preferenceKey)
    let controller = FakeLaunchAtLoginController(status: .unavailable)

    let model = LaunchAtLoginModel(
        defaults: defaults,
        controller: controller
    )

    #expect(
        model.presentation
            == LaunchAtLoginPresentation(
                isOn: false,
                isInteractive: false,
                statusTitle: "Unavailable in this build",
                guidance: "Open StayPane manually after login. Automatic Session Recovery after logout or restart is not available in this build.",
                showsSettingsAction: false
            )
    )
    #expect(controller.requestedValues.isEmpty)
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
        model.presentation.guidance
            == "Turn this on if you want StayPane to recover an unfinished Session after login."
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
