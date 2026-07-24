import Combine
import CoreGraphics
import Foundation

enum FloatingTimerSize: String, CaseIterable, Equatable, Hashable, Sendable {
    case small
    case medium
    case large

    var displayName: String {
        rawValue.capitalized
    }

    func stepped(by offset: Int) -> FloatingTimerSize {
        guard let currentIndex = Self.allCases.firstIndex(of: self) else {
            return self
        }
        let destination = min(
            max(currentIndex + offset, Self.allCases.startIndex),
            Self.allCases.index(before: Self.allCases.endIndex)
        )
        return Self.allCases[destination]
    }
}

struct FloatingTimerPreferences: Equatable {
    var isVisible: Bool
    var isCollapsed: Bool
    var size: FloatingTimerSize
    var origin: CGPoint?
}

@MainActor
final class FloatingTimerPreferenceModel: ObservableObject {
    @Published private(set) var value: FloatingTimerPreferences

    private enum Key {
        static let isCollapsed = "floatingTimerIsCollapsed"
        static let size = "floatingTimerSize"
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
            size: FloatingTimerSize(
                rawValue: defaults.string(forKey: Key.size) ?? ""
            ) ?? .medium,
            origin: origin
        )
    }

    var canDecreaseSize: Bool {
        value.size != .small
    }

    var canIncreaseSize: Bool {
        value.size != .large
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

    func decreaseSize() {
        setSize(value.size.stepped(by: -1))
    }

    func increaseSize() {
        setSize(value.size.stepped(by: 1))
    }

    func setSize(_ size: FloatingTimerSize) {
        guard value.size != size else {
            return
        }
        value.size = size
        save()
    }

    func move(to origin: CGPoint?) {
        guard value.origin != origin else {
            return
        }
        value.origin = origin
        save()
    }

    func resetPosition() {
        move(to: nil)
    }

    private func save() {
        defaults.set(value.isCollapsed, forKey: Key.isCollapsed)
        defaults.set(value.size.rawValue, forKey: Key.size)
        if let origin = value.origin {
            defaults.set(origin.x, forKey: Key.originX)
            defaults.set(origin.y, forKey: Key.originY)
        } else {
            defaults.removeObject(forKey: Key.originX)
            defaults.removeObject(forKey: Key.originY)
        }
    }
}
