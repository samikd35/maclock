import AppKit
import Combine
import SwiftUI

@MainActor
final class StayPanePanelController: NSWindowController, NSWindowDelegate {
    private let defaults: UserDefaults
    private var presentation: StayPanePanelPresentation = .setup
    private var cancellables: Set<AnyCancellable> = []
    private var isApplyingPresentation = false

    init(
        model: StayPaneModel,
        floatingTimerPreferences: FloatingTimerPreferenceModel,
        launchAtLoginModel: LaunchAtLoginModel,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        let initial = StayPanePanelPresentation.resolve(
            state: model.state,
            isReviewing: model.isReviewing,
            isOnboardingPresented: model.shouldPresentOnboarding
        )
        presentation = initial

        let panel = Self.makeWindow(for: initial)
        panel.contentView = NSHostingView(
            rootView: StayPaneMenuView(
                model: model,
                floatingTimerPreferences: floatingTimerPreferences,
                launchAtLoginModel: launchAtLoginModel
            )
        )

        super.init(window: panel)
        panel.delegate = self
        restoreFrame(for: initial, preferredScreen: Self.activeScreen())

        Publishers.CombineLatest3(
            model.$state.removeDuplicates(),
            model.$isReviewing.removeDuplicates(),
            model.$isOnboardingPresented.removeDuplicates()
        )
        .map { state, isReviewing, isOnboardingPresented in
            StayPanePanelPresentation.resolve(
                state: state,
                isReviewing: isReviewing,
                isOnboardingPresented: isOnboardingPresented
            )
        }
        .removeDuplicates()
        .sink { [weak self] nextPresentation in
            self?.apply(nextPresentation)
        }
        .store(in: &cancellables)
    }

    required init?(coder: NSCoder) {
        nil
    }

    static func makeWindow(
        for presentation: StayPanePanelPresentation
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(
                origin: .zero,
                size: presentation.preferredContentSize
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        window.title = presentation.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentMinSize = presentation.minimumContentSize
        return window
    }

    func showPanel() {
        guard let window else {
            return
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.setFrame(
            Self.constrained(
                frame: window.frame,
                to: window.screen ?? Self.activeScreen()
            ),
            display: false
        )
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func closePanel() {
        window?.close()
    }

    func windowDidMove(_ notification: Notification) {
        saveCurrentFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveCurrentFrame()
    }

    func windowWillClose(_ notification: Notification) {
        saveCurrentFrame()
    }

    private func apply(_ nextPresentation: StayPanePanelPresentation) {
        guard nextPresentation != presentation, let window else {
            return
        }
        saveCurrentFrame()
        presentation = nextPresentation
        window.title = nextPresentation.title
        window.contentMinSize = nextPresentation.minimumContentSize
        restoreFrame(
            for: nextPresentation,
            preferredScreen: window.screen ?? Self.activeScreen()
        )
    }

    private func restoreFrame(
        for presentation: StayPanePanelPresentation,
        preferredScreen: NSScreen?
    ) {
        guard let window else {
            return
        }
        let desiredFrame: CGRect
        if let savedFrame = savedFrame(for: presentation) {
            desiredFrame = savedFrame
        } else {
            let contentRect = CGRect(
                origin: .zero,
                size: presentation.preferredContentSize
            )
            var frame = window.frameRect(forContentRect: contentRect)
            let visibleFrame = preferredScreen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? frame
            frame.origin = CGPoint(
                x: visibleFrame.midX - frame.width / 2,
                y: visibleFrame.midY - frame.height / 2
            )
            desiredFrame = frame
        }

        isApplyingPresentation = true
        window.setFrame(
            Self.constrained(
                frame: desiredFrame,
                to: preferredScreen
            ),
            display: true,
            animate: window.isVisible
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        isApplyingPresentation = false
    }

    private func saveCurrentFrame() {
        guard !isApplyingPresentation, let frame = window?.frame else {
            return
        }
        defaults.set(
            NSStringFromRect(frame),
            forKey: frameKey(for: presentation)
        )
    }

    private func savedFrame(
        for presentation: StayPanePanelPresentation
    ) -> CGRect? {
        guard let value = defaults.string(
            forKey: frameKey(for: presentation)
        ) else {
            return nil
        }
        let frame = NSRectFromString(value)
        guard frame.width > 0, frame.height > 0 else {
            return nil
        }
        return frame
    }

    private func frameKey(
        for presentation: StayPanePanelPresentation
    ) -> String {
        "statusPanelFrame.\(presentation.rawValue)"
    }

    static func constrained(
        frame: CGRect,
        to preferredScreen: NSScreen?
    ) -> CGRect {
        let screen = preferredScreen
            ?? NSScreen.screens.max { left, right in
                intersectionArea(left.visibleFrame, frame)
                    < intersectionArea(right.visibleFrame, frame)
            }
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return frame
        }

        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let maximumX = visibleFrame.maxX - width
        let maximumY = visibleFrame.maxY - height
        return CGRect(
            x: min(max(frame.minX, visibleFrame.minX), maximumX),
            y: min(max(frame.minY, visibleFrame.minY), maximumY),
            width: width,
            height: height
        )
    }

    private static func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first {
            $0.frame.contains(mouseLocation)
        } ?? NSApplication.shared.keyWindow?.screen ?? NSScreen.main
    }

    private static func intersectionArea(
        _ left: CGRect,
        _ right: CGRect
    ) -> CGFloat {
        let intersection = left.intersection(right)
        guard !intersection.isNull else {
            return 0
        }
        return intersection.width * intersection.height
    }
}
