import Foundation
import Testing
@testable import StayPaneBridgeProtocol

@Test func localBridgeTransportsValidatedMessagesInBothDirections() throws {
    let socketURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("staypane-\(UUID().uuidString).sock")
    defer { try? FileManager.default.removeItem(at: socketURL) }
    let listener = try LocalBridgeListener(socketURL: socketURL)
    let client = try LocalBridgeClient(socketURL: socketURL)
    let hello = BridgeMessage.hello(
        extensionIdentifier: StayPaneBridgeConstants.extensionIdentifier,
        profileIdentifier: "profile-one"
    )

    try client.send(hello)
    let events = try listener.poll()

    let connected = try #require(
        events.compactMap { event -> BridgeConnectionIdentifier? in
            guard case let .connected(connection) = event else {
                return nil
            }
            return connection
        }.first
    )
    #expect(events.contains(.message(connection: connected, message: hello)))

    let acknowledgment = BridgeMessage.helloAcknowledged(
        profileIdentifier: "profile-one"
    )
    try listener.send(acknowledgment, to: connected)
    #expect(try client.readNextMessage() == acknowledgment)
}

@Test func localBridgeRejectsMessagesSentInTheWrongDirection() throws {
    let socketURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("staypane-\(UUID().uuidString).sock")
    defer { try? FileManager.default.removeItem(at: socketURL) }
    let listener = try LocalBridgeListener(socketURL: socketURL)
    let client = try LocalBridgeClient(socketURL: socketURL)

    #expect(throws: BridgeProtocolError.invalidSchema) {
        try client.send(.requestTabs(profileIdentifier: "profile-one"))
    }
    withExtendedLifetime(listener) {}
}
