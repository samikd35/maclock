import Darwin
import Foundation

public enum NativeMessagingHostRunner {
    public static func run(
        callerOrigin: String,
        input: FileHandle = .standardInput,
        output: FileHandle = .standardOutput,
        socketURL: URL = StayPaneBridgeSocketLocation.defaultURL
    ) throws {
        guard NativeHostOriginValidator.isAllowed(callerOrigin) else {
            throw BridgeProtocolError.invalidSchema
        }
        let client = try LocalBridgeClient(socketURL: socketURL)
        var inputBuffer = Data()
        var descriptors = [
            pollfd(
                fd: input.fileDescriptor,
                events: Int16(POLLIN | POLLHUP),
                revents: 0
            ),
            pollfd(
                fd: client.fileDescriptor,
                events: Int16(POLLIN | POLLHUP),
                revents: 0
            )
        ]

        while true {
            let result = Darwin.poll(&descriptors, nfds_t(descriptors.count), -1)
            if result < 0 {
                if errno == EINTR {
                    continue
                }
                throw LocalBridgeSocketError.systemCallFailed(errno)
            }

            if descriptors[0].revents & Int16(POLLIN) != 0 {
                var bytes = [UInt8](repeating: 0, count: 8_192)
                let count = Darwin.read(
                    input.fileDescriptor,
                    &bytes,
                    bytes.count
                )
                if count <= 0 {
                    client.finishSending()
                    return
                }
                inputBuffer.append(contentsOf: bytes.prefix(count))
                let payloads = try NativeMessageFramer.extractMessages(
                    from: &inputBuffer
                )
                for payload in payloads {
                    let message = try BridgeMessageCodec.decode(payload)
                    guard message.direction == .extensionToNative else {
                        throw BridgeProtocolError.invalidSchema
                    }
                    try client.send(message)
                }
            }

            if descriptors[1].revents & Int16(POLLIN) != 0 {
                let result = try client.readAvailableMessages()
                for message in result.messages {
                    let payload = try BridgeMessageCodec.encode(message)
                    try output.write(
                        contentsOf: NativeMessageFramer.frame(payload)
                    )
                }
                if result.isClosed {
                    return
                }
            }

            if descriptors[0].revents & Int16(POLLHUP | POLLERR) != 0 {
                client.finishSending()
                return
            }
            if descriptors[1].revents & Int16(POLLHUP | POLLERR) != 0 {
                return
            }
            descriptors[0].revents = 0
            descriptors[1].revents = 0
        }
    }
}
