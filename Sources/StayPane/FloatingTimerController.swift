import AppKit
import Combine
import SwiftUI

final class FloatingTimerPanel: NSPanel {
    static let requiredCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllApplications,
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .ignoresCycle
    ]

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
final class FloatingTimerController: NSObject, NSWindowDelegate {
    private let model: StayPaneModel
    private let preferences: FloatingTimerPreferenceModel
    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var isApplyingFrame = false
    private var lastAppliedLayout: AppliedLayout?

    private struct AppliedLayout: Equatable {
        let isCollapsed: Bool
        let size: FloatingTimerSize
        let origin: CGPoint?
    }

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

    private func makePanel() -> FloatingTimerPanel {
        let panel = FloatingTimerPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior =
            FloatingTimerPanel.requiredCollectionBehavior
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
        let layout = AppliedLayout(
            isCollapsed: value.isCollapsed,
            size: value.size,
            origin: value.origin
        )
        if let lastAppliedLayout,
           lastAppliedLayout.isCollapsed == layout.isCollapsed,
           lastAppliedLayout.size == layout.size,
           lastAppliedLayout.origin != layout.origin
        {
            if value.origin == panel.frame.origin {
                self.lastAppliedLayout = layout
                return
            }
            isApplyingFrame = true
            panel.setFrameOrigin(
                resolvedOrigin(
                    savedOrigin: value.origin,
                    size: panel.frame.size
                )
            )
            isApplyingFrame = false
            self.lastAppliedLayout = layout
            preferences.move(to: panel.frame.origin)
            return
        }
        guard lastAppliedLayout != layout else {
            return
        }
        let metrics = FloatingTimerLayoutMetrics.resolve(
            size: value.size,
            isCollapsed: value.isCollapsed
        )
        let previousFrame = panel.frame.size == .zero
            ? nil
            : panel.frame

        isApplyingFrame = true
        panel.setContentSize(metrics.contentSize)
        if let previousFrame {
            let previousTopLeft = CGPoint(
                x: previousFrame.minX,
                y: previousFrame.maxY
            )
            let desiredOrigin = CGPoint(
                x: previousTopLeft.x,
                y: previousTopLeft.y - panel.frame.height
            )
            panel.setFrameOrigin(
                constrainedOrigin(
                    desiredOrigin,
                    size: panel.frame.size,
                    preferredScreen: screen(for: previousFrame)
                )
            )
        } else {
            panel.setFrameOrigin(
                resolvedOrigin(
                    savedOrigin: value.origin,
                    size: panel.frame.size
                )
            )
        }
        isApplyingFrame = false
        lastAppliedLayout = layout

        preferences.move(to: panel.frame.origin)
    }

    private func screen(for frame: CGRect) -> NSScreen? {
        let candidate = NSScreen.screens.max { left, right in
            intersectionArea(left.visibleFrame, frame)
                < intersectionArea(right.visibleFrame, frame)
        }
        guard let candidate,
              intersectionArea(candidate.visibleFrame, frame) > 0
        else {
            return nil
        }
        return candidate
    }

    private func intersectionArea(_ left: CGRect, _ right: CGRect) -> CGFloat {
        let intersection = left.intersection(right)
        guard !intersection.isNull else {
            return 0
        }
        return intersection.width * intersection.height
    }

    private func constrainedOrigin(
        _ origin: CGPoint,
        size: CGSize,
        preferredScreen: NSScreen?
    ) -> CGPoint {
        let visibleFrame = preferredScreen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        return CGPoint(
            x: min(max(origin.x, visibleFrame.minX), maximumX),
            y: min(max(origin.y, visibleFrame.minY), maximumY)
        )
    }

    private func resolvedOrigin(
        savedOrigin: CGPoint?,
        size: CGSize
    ) -> CGPoint {
        guard let savedOrigin else {
            return defaultOrigin(for: size)
        }
        let desiredFrame = CGRect(
            origin: savedOrigin,
            size: size
        )
        return constrainedOrigin(
            savedOrigin,
            size: size,
            preferredScreen: screen(for: desiredFrame)
        )
    }

    private func defaultOrigin(for size: CGSize) -> CGPoint {
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        return constrainedOrigin(
            CGPoint(
                x: visibleFrame.maxX - size.width - 24,
                y: visibleFrame.maxY - size.height - 24
            ),
            size: size,
            preferredScreen: NSScreen.main
        )
    }
}
