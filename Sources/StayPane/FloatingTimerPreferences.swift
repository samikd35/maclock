import Combine
import CoreGraphics
import Foundation

struct FloatingTimerPreferences: Equatable {
    var isVisible: Bool
    var isCollapsed: Bool
    var origin: CGPoint?
}

@MainActor
final class FloatingTimerPreferenceModel: ObservableObject {
    @Published private(set) var value: FloatingTimerPreferences

    private enum Key {
        static let isCollapsed = "floatingTimerIsCollapsed"
        static let originX = "floatingTimerOriginX"
        static let originY = "floatingTimerOriginY"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let origin: CGPoint?
        if defaults.object(forKey: Key.originX) != nil,
           defaults.object(forKey: Key.originY) != nil
        {
            origin = CGPoint(
                x: defaults.double(forKey: Key.originX),
                y: defaults.double(forKey: Key.originY)
            )
        } else {
            origin = nil
        }
        value = FloatingTimerPreferences(
            isVisible: true,
            isCollapsed: defaults.bool(forKey: Key.isCollapsed),
            origin: origin
        )
    }

    func setVisible(_ isVisible: Bool) {
        guard value.isVisible != isVisible else {
            return
        }
        value.isVisible = isVisible
        save()
    }

    func toggleCollapsed() {
        setCollapsed(!value.isCollapsed)
    }

    func setCollapsed(_ isCollapsed: Bool) {
        guard value.isCollapsed != isCollapsed else {
            return
        }
        value.isCollapsed = isCollapsed
        save()
    }

    func move(to origin: CGPoint) {
        guard value.origin != origin else {
            return
        }
        value.origin = origin
        save()
    }

    private func save() {
        defaults.set(value.isCollapsed, forKey: Key.isCollapsed)
        if let origin = value.origin {
            defaults.set(origin.x, forKey: Key.originX)
            defaults.set(origin.y, forKey: Key.originY)
        } else {
            defaults.removeObject(forKey: Key.originX)
            defaults.removeObject(forKey: Key.originY)
        }
    }
}
