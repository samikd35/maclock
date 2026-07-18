import AppKit

@MainActor
enum FocusSettingsOpener {
    static func open() -> Bool {
        let candidateURLs = [
            "x-apple.systempreferences:com.apple.Focus-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        return candidateURLs.contains { candidate in
            guard let url = URL(string: candidate) else {
                return false
            }
            return NSWorkspace.shared.open(url)
        }
    }
}
