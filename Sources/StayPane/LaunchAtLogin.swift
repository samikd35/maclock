import Combine
import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}

struct LaunchAtLoginPresentation: Equatable {
    let isOn: Bool
    let isInteractive: Bool
    let statusTitle: String
    let guidance: String
    let showsSettingsAction: Bool
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

    var presentation: LaunchAtLoginPresentation {
        switch status {
        case .enabled:
            LaunchAtLoginPresentation(
                isOn: true,
                isInteractive: true,
                statusTitle: "Active",
                guidance: "StayPane will open after login so it can recover an unfinished Session.",
                showsSettingsAction: false
            )
        case .disabled:
            LaunchAtLoginPresentation(
                isOn: false,
                isInteractive: true,
                statusTitle: "Off",
                guidance: "Turn this on if you want StayPane to recover an unfinished Session after login.",
                showsSettingsAction: false
            )
        case .requiresApproval:
            LaunchAtLoginPresentation(
                isOn: true,
                isInteractive: true,
                statusTitle: "Approval required",
                guidance: "Approve StayPane in System Settings → Login Items before relying on automatic Session Recovery.",
                showsSettingsAction: true
            )
        case .unavailable:
            LaunchAtLoginPresentation(
                isOn: false,
                isInteractive: false,
                statusTitle: "Unavailable in this build",
                guidance: "Open StayPane manually after login. Automatic Session Recovery after logout or restart is not available in this build.",
                showsSettingsAction: false
            )
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
