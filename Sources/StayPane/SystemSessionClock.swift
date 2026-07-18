import Foundation
import StayPaneCore

@MainActor
final class SystemSessionClock: SessionClock {
    private let continuousOrigin = ContinuousClock.now

    var now: Date { Date() }
    var continuousNow: TimeInterval {
        let duration = continuousOrigin.duration(to: .now)
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
