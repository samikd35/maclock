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
    private var isLiveResizing = false
    private var movePersistenceTask: Task<Void, Never>?
    private var lastAppliedLayout: AppliedLayout?

    private struct AppliedLayout: Equatable {
        let isCollapsed: Bool
        let scale: Double
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

        NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )
        .sink { [weak self] _ in
            self?.reclampPanel()
        }
        .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didWakeNotification
        )
        .sink { [weak self] _ in
            self?.reclampPanel()
        }
        .store(in: &cancellables)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingFrame, !isLiveResizing, let panel else {
            return
        }
        scheduleMovePersistence(for: panel)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        isLiveResizing = true
    }

    func windowWillResize(
        _ sender: NSWindow,
        to frameSize: NSSize
    ) -> NSSize {
        guard !isApplyingFrame else {
            return frameSize
        }
        let currentContentSize = sender.contentRect(
            forFrameRect: sender.frame
        ).size
        let proposedContentSize = sender.contentRect(
            forFrameRect: CGRect(origin: .zero, size: frameSize)
        ).size
        let scale = FloatingTimerResizeGeometry.scale(
            forProposedSize: proposedContentSize,
            currentSize: currentContentSize,
            currentScale: preferences.value.scale,
            isCollapsed: preferences.value.isCollapsed
        )
        preferences.updateScaleDuringLiveResize(scale)
        let canonicalContentSize = FloatingTimerLayoutMetrics.resolve(
            scale: scale,
            isCollapsed: preferences.value.isCollapsed
        ).contentSize
        return sender.frameRect(
            forContentRect: CGRect(
                origin: .zero,
                size: canonicalContentSize
            )
        ).size
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel else {
            return
        }
        isLiveResizing = false
        preferences.persistScale()
        preferences.move(to: panel.frame.origin)
        lastAppliedLayout = AppliedLayout(
            isCollapsed: preferences.value.isCollapsed,
            scale: preferences.value.scale,
            origin: panel.frame.origin
        )
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
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
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
        panel.contentMinSize = FloatingTimerLayoutMetrics.resolve(
            scale: 0,
            isCollapsed: preferences.value.isCollapsed
        ).contentSize
        panel.contentMaxSize = FloatingTimerLayoutMetrics.resolve(
            scale: 1,
            isCollapsed: preferences.value.isCollapsed
        ).contentSize
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
            scale: value.scale,
            origin: value.origin
        )
        if panel.inLiveResize {
            lastAppliedLayout = layout
            return
        }
        if let lastAppliedLayout,
           lastAppliedLayout.isCollapsed == layout.isCollapsed,
           lastAppliedLayout.scale == layout.scale,
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
            scale: value.scale,
            isCollapsed: value.isCollapsed
        )
        panel.contentMinSize = FloatingTimerLayoutMetrics.resolve(
            scale: 0,
            isCollapsed: value.isCollapsed
        ).contentSize
        panel.contentMaxSize = FloatingTimerLayoutMetrics.resolve(
            scale: 1,
            isCollapsed: value.isCollapsed
        ).contentSize
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

    private func reclampPanel() {
        guard let panel, panel.isVisible, !panel.inLiveResize else {
            return
        }
        let origin = constrainedOrigin(
            panel.frame.origin,
            size: panel.frame.size,
            preferredScreen: screen(for: panel.frame) ?? NSScreen.main
        )
        guard origin != panel.frame.origin else {
            return
        }
        isApplyingFrame = true
        panel.setFrameOrigin(origin)
        isApplyingFrame = false
        preferences.move(to: origin)
        lastAppliedLayout = AppliedLayout(
            isCollapsed: preferences.value.isCollapsed,
            scale: preferences.value.scale,
            origin: origin
        )
    }

    private func scheduleMovePersistence(
        for panel: NSPanel
    ) {
        movePersistenceTask?.cancel()
        movePersistenceTask = Task { [weak self, weak panel] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self, let panel else {
                return
            }
            if NSEvent.pressedMouseButtons != 0 {
                scheduleMovePersistence(for: panel)
                return
            }
            let origin = constrainedOrigin(
                panel.frame.origin,
                size: panel.frame.size,
                preferredScreen: screen(for: panel.frame) ?? NSScreen.main
            )
            if origin != panel.frame.origin {
                isApplyingFrame = true
                panel.setFrameOrigin(origin)
                isApplyingFrame = false
            }
            preferences.move(to: origin)
            lastAppliedLayout = AppliedLayout(
                isCollapsed: preferences.value.isCollapsed,
                scale: preferences.value.scale,
                origin: origin
            )
        }
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
