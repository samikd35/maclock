import Foundation
import StayPaneCore

struct RecoverableWindowReference: Codable, Equatable, Hashable, Sendable {
    let windowIdentifier: WindowIdentifier
    let bundleIdentifier: String
    let processIdentifier: Int32
    let accessibilityIdentifier: String
}
