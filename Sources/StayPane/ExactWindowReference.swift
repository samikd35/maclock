import Foundation
import StayPaneCore

struct ExactWindowReference: Codable, Equatable, Hashable, Sendable {
    let windowIdentifier: WindowIdentifier
    let bundleIdentifier: String
    let processIdentifier: Int32
    let accessibilityIdentifier: String
}
