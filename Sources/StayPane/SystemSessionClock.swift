import Foundation
import StayPaneCore

@MainActor
final class SystemSessionClock: SessionClock {
    var now: Date { Date() }
    var continuousNow: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
