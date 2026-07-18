import Combine
import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LaunchAtLoginControlling: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

@MainActor
final class SystemLaunchAtLoginController: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            .enabled
        case .notRegistered:
            .disabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else {
                return
            }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status != .notRegistered else {
                return
            }
            try SMAppService.mainApp.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class LaunchAtLoginModel: ObservableObject {
    nonisolated static let preferenceKey = "launchAtLoginEnabled"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var status: LaunchAtLoginStatus
    @Published private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let controller: any LaunchAtLoginControlling

    init(
        defaults: UserDefaults = .standard,
        controller: any LaunchAtLoginControlling = SystemLaunchAtLoginController()
    ) {
        self.defaults = defaults
        self.controller = controller
        let hasPreference = defaults.object(forKey: Self.preferenceKey) != nil
        isEnabled = hasPreference
            ? defaults.bool(forKey: Self.preferenceKey)
            : true
        status = controller.status

        if !hasPreference {
            defaults.set(true, forKey: Self.preferenceKey)
        }
        applyDesiredRegistrationIfNeeded()
    }

    var isEffective: Bool {
        status == .enabled
    }

    var recoveryLimitation: String? {
        if !isEnabled {
            return "StayPane cannot automatically resume an unfinished Session after login while Launch at Login is disabled."
        }
        switch status {
        case .enabled:
            return nil
        case .requiresApproval:
            return "Approve StayPane in System Settings → Login Items so unfinished Sessions can resume after login."
        case .disabled, .unavailable:
            return "Launch at Login is not currently available, so automatic Session recovery after login is not guaranteed."
        }
    }

    func setEnabled(_ enabled: Bool) {
        let previousValue = isEnabled
        do {
            try controller.setEnabled(enabled)
            isEnabled = enabled
            defaults.set(enabled, forKey: Self.preferenceKey)
            status = controller.status
            errorMessage = nil
        } catch {
            isEnabled = previousValue
            status = controller.status
            errorMessage = "StayPane could not update Launch at Login: \(error.localizedDescription)"
        }
    }

    func refresh() {
        status = controller.status
    }

    func openSystemSettings() {
        controller.openSystemSettings()
    }

    private func applyDesiredRegistrationIfNeeded() {
        guard isEnabled, status == .disabled else {
            return
        }
        do {
            try controller.setEnabled(true)
            status = controller.status
        } catch {
            status = controller.status
            errorMessage = "StayPane could not enable Launch at Login automatically: \(error.localizedDescription)"
        }
    }
}
