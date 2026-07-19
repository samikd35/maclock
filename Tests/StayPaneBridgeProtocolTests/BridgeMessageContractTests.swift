import Foundation
import Testing
@testable import StayPaneBridgeProtocol

@Test func handshakeMessageRoundTripsThroughTheVersionedContract() throws {
    let json = Data(
        #"{"version":3,"type":"hello","extensionId":"hoofhoedlagpoclhkgnkmejaihaapoke","profileId":"profile-one"}"#.utf8
    )

    let message = try BridgeMessageCodec.decode(json)

    #expect(
        message == .hello(
            extensionIdentifier: "hoofhoedlagpoclhkgnkmejaihaapoke",
            profileIdentifier: "profile-one"
        )
    )
    #expect(try BridgeMessageCodec.decode(BridgeMessageCodec.encode(message)) == message)
    #expect(message.direction == .extensionToNative)
}

@Test func tabSnapshotCarriesOnlyValidatedLocalPickerFields() throws {
    let message = BridgeMessage.tabsSnapshot(
        profileIdentifier: "profile-one",
        tabs: [
            BridgeTabSnapshot(
                tabIdentifier: 41,
                windowIdentifier: 9,
                title: "Project plan",
                url: "https://work.example/project",
                faviconDataURL: "data:image/png;base64,iVBORw0KGgo=",
                isActive: true,
                isIncognito: false
            )
        ]
    )

    let decoded = try BridgeMessageCodec.decode(
        BridgeMessageCodec.encode(message)
    )

    #expect(decoded == message)
    #expect(decoded.direction == .extensionToNative)
}

@Test func multiTabStartConfirmationRoundTripsTowardTheMacApp() throws {
    let message = BridgeMessage.enforcementStarted(
        profileIdentifier: "profile-one",
        tabIdentifiers: [41, 42]
    )

    #expect(
        try BridgeMessageCodec.decode(BridgeMessageCodec.encode(message))
            == message
    )
    #expect(message.direction == .extensionToNative)
}

@Test func mixedNavigationScopesRoundTripInOneAtomicStartCommand() throws {
    let message = BridgeMessage.beginEnforcement(
        profileIdentifier: "profile-one",
        targets: [
            BridgeEnforcementTarget(
                tabIdentifier: 41,
                windowIdentifier: 9,
                navigationScope: .currentWebsite(
                    initialURL: "https://work.example/project?view=board"
                )
            ),
            BridgeEnforcementTarget(
                tabIdentifier: 42,
                windowIdentifier: 10,
                navigationScope: .exactPage(
                    initialURL: "https://docs.example/reference?v=1#heading"
                )
            )
        ]
    )

    #expect(
        try BridgeMessageCodec.decode(BridgeMessageCodec.encode(message))
            == message
    )
    #expect(message.direction == .nativeToExtension)
}

@Test func closedTabTargetNoticeRoundTripsWithoutBrowsingContent() throws {
    let message = BridgeMessage.tabTargetClosed(
        profileIdentifier: "profile-one",
        tabIdentifier: 41
    )

    let encoded = try BridgeMessageCodec.encode(message)

    #expect(try BridgeMessageCodec.decode(encoded) == message)
    #expect(!String(decoding: encoded, as: UTF8.self).contains("http"))
}

@Test func blockedNavigationNoticeCarriesNoBrowsingContent() throws {
    let message = BridgeMessage.blockedNavigation(
        profileIdentifier: "profile-one",
        tabIdentifier: 41
    )

    let encoded = try BridgeMessageCodec.encode(message)

    #expect(try BridgeMessageCodec.decode(encoded) == message)
    #expect(message.direction == .extensionToNative)
    #expect(!String(decoding: encoded, as: UTF8.self).contains("https"))
}

@Test func blockedActivationNamesTheAvailableTabTarget() throws {
    let message = BridgeMessage.blockedTabActivation(
        profileIdentifier: "profile-one",
        attemptedTabIdentifier: 90,
        availableTabIdentifier: 41
    )

    #expect(
        try BridgeMessageCodec.decode(BridgeMessageCodec.encode(message))
            == message
    )
}

@Test func loadingTabFailureRoundTripsWithoutBrowsingContent() throws {
    let message = BridgeMessage.enforcementError(
        profileIdentifier: "profile-one",
        code: .targetNotReady
    )

    let encoded = try BridgeMessageCodec.encode(message)

    #expect(try BridgeMessageCodec.decode(encoded) == message)
    #expect(!String(decoding: encoded, as: UTF8.self).contains("http"))
}

@Test(arguments: [
    #"{"version":1,"type":"hello","extensionId":"hoofhoedlagpoclhkgnkmejaihaapoke","profileId":"profile-one"}"#,
    #"{"version":3,"type":"hello","extensionId":"wrong","profileId":"profile-one"}"#,
    #"{"version":3,"type":"hello","extensionId":"hoofhoedlagpoclhkgnkmejaihaapoke","profileId":"profile-one","extra":true}"#,
    #"{"version":3,"type":"tabsSnapshot","profileId":"profile-one","tabs":[{"tabId":-1,"windowId":9,"title":"Bad","url":"https://example.com","active":true,"incognito":false}]}"#,
    #"{"version":3,"type":"tabsSnapshot","profileId":"profile-one","tabs":[{"tabId":1,"windowId":9,"title":"Bad","url":"https://example.com","faviconDataUrl":"data:image/png;base64,not@@@","active":true,"incognito":false}]}"#,
    #"{"version":3,"type":"tabsSnapshot","profileId":"profile-one","tabs":[{"tabId":1,"windowId":9,"title":"Bad","url":"https://example.com","faviconDataUrl":"data:image/png;base64,SGVsbG8=","active":true,"incognito":false}]}"#,
    #"{"version":3,"type":"beginEnforcement","profileId":"profile-one","targets":[{"tabId":1,"windowId":9,"navigationScope":{"type":"currentWebsite","initialUrl":"chrome://settings"}}]}"#,
    #"{"version":3,"type":"unknown"}"#
])
func malformedNativeMessagesAreRejected(_ json: String) {
    #expect(throws: BridgeProtocolError.self) {
        try BridgeMessageCodec.decode(Data(json.utf8))
    }
}

@Test func nativeHostOriginMustExactlyMatchTheExpectedUnpackedExtension() {
    #expect(
        NativeHostOriginValidator.isAllowed(
            "chrome-extension://hoofhoedlagpoclhkgnkmejaihaapoke/"
        )
    )
    #expect(
        !NativeHostOriginValidator.isAllowed(
            "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"
        )
    )
    #expect(
        !NativeHostOriginValidator.isAllowed(
            "chrome-extension://hoofhoedlagpoclhkgnkmejaihaapoke/extra"
        )
    )
}

@Test func nativeFramingWaitsForCompleteMessagesAndRejectsOversizeInput() throws {
    let payload = Data(#"{"version":3,"type":"requestTabs","profileId":"profile-one"}"#.utf8)
    let framed = try NativeMessageFramer.frame(payload)
    var incomplete = Data(framed.dropLast())

    #expect(try NativeMessageFramer.extractMessages(from: &incomplete).isEmpty)

    incomplete.append(framed.last!)
    #expect(try NativeMessageFramer.extractMessages(from: &incomplete) == [payload])
    #expect(incomplete.isEmpty)

    let oversizedLength = UInt32(NativeMessageFramer.maximumMessageSize + 1)
        .littleEndian
    var oversized = withUnsafeBytes(of: oversizedLength) { Data($0) }
    #expect(throws: BridgeProtocolError.self) {
        try NativeMessageFramer.extractMessages(from: &oversized)
    }
}
