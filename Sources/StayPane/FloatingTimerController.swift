import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingTimerController: NSObject, NSWindowDelegate {
    private let model: StayPaneModel
    private let preferences: FloatingTimerPreferenceModel
    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var isApplyingFrame = false
    private var lastAppliedCollapsedState: Bool?

    init(
        model: StayPaneModel,
        preferences: FloatingTimerPreferenceModel
    ) {
        self.model = model
        self.preferences = preferences
        super.init()

        model.$state
            .removeDuplicates()
            .combineLatest(preferences.$value.removeDuplicates())
            .sink { [weak self] _, value in
                self?.synchronize(with: value)
            }
            .store(in: &cancellables)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingFrame, let panel else {
            return
        }
        preferences.move(to: panel.frame.origin)
    }

    private func synchronize(with value: FloatingTimerPreferences) {
        guard model.sessionPresence.isEnforcing, value.isVisible else {
            panel?.orderOut(nil)
            return
        }

        let panel = panel ?? makePanel()
        apply(value, to: panel)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        self.panel = panel
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
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: FloatingTimerView(
                model: model,
                preferences: preferences
            )
        )
        return panel
    }

    private func apply(
        _ value: FloatingTimerPreferences,
        to panel: NSPanel
    ) {
        guard lastAppliedCollapsedState != value.isCollapsed else {
            return
        }
        let contentSize = value.isCollapsed
            ? CGSize(width: 190, height: 44)
            : CGSize(width: 250, height: 62)
        let previousTopLeft = panel.frame.size == .zero
            ? nil
            : CGPoint(x: panel.frame.minX, y: panel.frame.maxY)

        isApplyingFrame = true
        panel.setContentSize(contentSize)
        if let previousTopLeft {
            panel.setFrameTopLeftPoint(previousTopLeft)
        } else if let origin = value.origin,
                  isVisible(origin: origin, size: panel.frame.size)
        {
            panel.setFrameOrigin(origin)
        } else {
            panel.setFrameOrigin(defaultOrigin(for: panel.frame.size))
        }
        isApplyingFrame = false
        lastAppliedCollapsedState = value.isCollapsed

        preferences.move(to: panel.frame.origin)
    }

    private func isVisible(origin: CGPoint, size: CGSize) -> Bool {
        let frame = CGRect(origin: origin, size: size)
        return NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(frame)
        }
    }

    private func defaultOrigin(for size: CGSize) -> CGPoint {
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        return CGPoint(
            x: visibleFrame.maxX - size.width - 24,
            y: visibleFrame.maxY - size.height - 24
        )
    }
}
