import AppKit

@MainActor
final class WindowOutlineController {
    private var panel: NSPanel?

    func show(around accessibilityFrame: CGRect) {
        let panel = panel ?? makePanel()
        panel.setFrame(Self.appKitFrame(from: accessibilityFrame), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]

        let outlineView = NSView(frame: .zero)
        outlineView.wantsLayer = true
        outlineView.layer?.backgroundColor = NSColor.clear.cgColor
        outlineView.layer?.borderColor = NSColor.controlAccentColor.cgColor
        outlineView.layer?.borderWidth = 4
        outlineView.layer?.cornerRadius = 8
        panel.contentView = outlineView
        return panel
    }

    private static func appKitFrame(from accessibilityFrame: CGRect) -> CGRect {
        let mainScreenTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: accessibilityFrame.minX - 4,
            y: mainScreenTop - accessibilityFrame.maxY - 4,
            width: accessibilityFrame.width + 8,
            height: accessibilityFrame.height + 8
        )
    }
}
