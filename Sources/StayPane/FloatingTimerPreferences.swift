import Combine
import CoreGraphics
import Foundation

private enum LegacyFloatingTimerSize: String {
    case small
    case medium
    case large

    var scale: Double {
        switch self {
        case .small:
            0
        case .medium:
            0.5
        case .large:
            1
        }
    }
}

struct FloatingTimerPreferences: Equatable {
    var isVisible: Bool
    var isCollapsed: Bool
    var scale: Double
    var origin: CGPoint?
}

@MainActor
final class FloatingTimerPreferenceModel: ObservableObject {
    static let minimumScale = 0.0
    static let defaultScale = 0.5
    static let maximumScale = 1.0
    static let accessibilityScaleStep = 0.05

    @Published private(set) var value: FloatingTimerPreferences

    private enum Key {
        static let isCollapsed = "floatingTimerIsCollapsed"
        static let scale = "floatingTimerScale"
        static let legacySize = "floatingTimerSize"
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

        let scale: Double
        if defaults.object(forKey: Key.scale) != nil {
            scale = Self.clamped(defaults.double(forKey: Key.scale))
        } else if let legacy = LegacyFloatingTimerSize(
            rawValue: defaults.string(forKey: Key.legacySize) ?? ""
        ) {
            scale = legacy.scale
        } else {
            scale = Self.defaultScale
        }

        value = FloatingTimerPreferences(
            isVisible: true,
            isCollapsed: defaults.bool(forKey: Key.isCollapsed),
            scale: scale,
            origin: origin
        )
        defaults.set(scale, forKey: Key.scale)
    }

    var canDecreaseSize: Bool {
        value.scale > Self.minimumScale
    }

    var canIncreaseSize: Bool {
        value.scale < Self.maximumScale
    }

    var sizeDescription: String {
        switch value.scale {
        case ..<0.25:
            "Small"
        case 0.75...:
            "Large"
        default:
            "Medium"
        }
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
        adjustScale(by: -Self.accessibilityScaleStep)
    }

    func increaseSize() {
        adjustScale(by: Self.accessibilityScaleStep)
    }

    func adjustScale(by offset: Double) {
        setScale(value.scale + offset)
    }

    func setScale(_ scale: Double) {
        setScale(scale, persist: true)
    }

    func updateScaleDuringLiveResize(_ scale: Double) {
        setScale(scale, persist: false)
    }

    func persistScale() {
        defaults.set(value.scale, forKey: Key.scale)
    }

    func resetScale() {
        setScale(Self.defaultScale)
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

    private func setScale(_ scale: Double, persist: Bool) {
        let clampedScale = Self.clamped(scale)
        guard value.scale != clampedScale else {
            if persist {
                persistScale()
            }
            return
        }
        value.scale = clampedScale
        if persist {
            save()
        }
    }

    private static func clamped(_ scale: Double) -> Double {
        min(max(scale, minimumScale), maximumScale)
    }

    private func save() {
        defaults.set(value.isCollapsed, forKey: Key.isCollapsed)
        defaults.set(value.scale, forKey: Key.scale)
        if let origin = value.origin {
            defaults.set(origin.x, forKey: Key.originX)
            defaults.set(origin.y, forKey: Key.originY)
        } else {
            defaults.removeObject(forKey: Key.originX)
            defaults.removeObject(forKey: Key.originY)
        }
    }
}
