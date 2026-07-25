import Foundation
import StayPaneCore

struct DurationComponents: Equatable, Sendable {
    var hours: Int
    var minutes: Int
    var seconds: Int

    init(hours: Int, minutes: Int, seconds: Int) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
    }

    init(seconds totalSeconds: Int) {
        let nonnegativeSeconds = max(0, totalSeconds)
        hours = nonnegativeSeconds / 3_600
        minutes = (nonnegativeSeconds % 3_600) / 60
        seconds = nonnegativeSeconds % 60
    }

    var totalSeconds: Int {
        (hours * 3_600) + (minutes * 60) + seconds
    }

    var validationError: String? {
        guard (0...24).contains(hours) else {
            return "Hours must be between 0 and 24."
        }
        guard (0...59).contains(minutes) else {
            return "Minutes must be between 0 and 59."
        }
        guard (0...59).contains(seconds) else {
            return "Seconds must be between 0 and 59."
        }
        guard hours < 24 || (minutes == 0 && seconds == 0) else {
            return "24 hours is the maximum duration."
        }
        guard SessionDuration(seconds: totalSeconds) != nil else {
            return "Choose a duration from 10 seconds to 24 hours."
        }
        return nil
    }

    var validTotalSeconds: Int? {
        validationError == nil ? totalSeconds : nil
    }
}
