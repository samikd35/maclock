import Darwin
import Foundation

public struct BridgeConnectionIdentifier: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum LocalBridgeEvent: Equatable, Sendable {
    case connected(BridgeConnectionIdentifier)
    case message(
        connection: BridgeConnectionIdentifier,
        message: BridgeMessage
    )
    case rejected(BridgeConnectionIdentifier)
    case disconnected(BridgeConnectionIdentifier)
}

public enum LocalBridgeSocketError: Error, Equatable, Sendable {
    case pathTooLong
    case systemCallFailed(Int32)
    case connectionClosed
}

public enum StayPaneBridgeSocketLocation {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("StayPane", isDirectory: true)
            .appendingPathComponent("native-bridge.sock", isDirectory: false)
    }
}

public final class LocalBridgeServer {
    private struct Connection {
        let fileDescriptor: Int32
        var buffer = Data()
    }

    private let socketURL: URL
    private let listenerFileDescriptor: Int32
    private var connections: [BridgeConnectionIdentifier: Connection] = [:]

    public init(
        socketURL: URL = StayPaneBridgeSocketLocation.defaultURL
    ) throws {
        self.socketURL = socketURL
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = Darwin.unlink(socketURL.path)
        let listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw LocalBridgeSocketError.systemCallFailed(errno)
        }
        do {
            try configureSocket(listener, nonblocking: true)
            try withSocketAddress(path: socketURL.path) { address, length in
                guard Darwin.bind(listener, address, length) == 0 else {
                    throw LocalBridgeSocketError.systemCallFailed(errno)
                }
            }
            guard Darwin.listen(listener, 8) == 0 else {
                throw LocalBridgeSocketError.systemCallFailed(errno)
            }
            guard Darwin.chmod(socketURL.path, 0o600) == 0 else {
                throw LocalBridgeSocketError.systemCallFailed(errno)
            }
            listenerFileDescriptor = listener
        } catch {
            Darwin.close(listener)
            _ = Darwin.unlink(socketURL.path)
            throw error
        }
    }

    deinit {
        for connection in connections.values {
            Darwin.close(connection.fileDescriptor)
        }
        Darwin.close(listenerFileDescriptor)
        _ = Darwin.unlink(socketURL.path)
    }

    public func poll() throws -> [LocalBridgeEvent] {
        var events: [LocalBridgeEvent] = []
        while true {
            let accepted = Darwin.accept(listenerFileDescriptor, nil, nil)
            guard accepted >= 0 else {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    break
                }
                throw LocalBridgeSocketError.systemCallFailed(errno)
            }
            try configureSocket(accepted, nonblocking: true)
            let identifier = BridgeConnectionIdentifier()
            connections[identifier] = Connection(fileDescriptor: accepted)
            events.append(.connected(identifier))
        }

        for identifier in Array(connections.keys) {
            guard var connection = connections[identifier] else {
                continue
            }
            var shouldDisconnect = false
            while true {
                var bytes = [UInt8](repeating: 0, count: 8_192)
                let count = Darwin.recv(
                    connection.fileDescriptor,
                    &bytes,
                    bytes.count,
                    0
                )
                if count > 0 {
                    connection.buffer.append(contentsOf: bytes.prefix(count))
                    continue
                }
                if count == 0 {
                    shouldDisconnect = true
                    break
                }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    break
                }
                shouldDisconnect = true
                break
            }

            do {
                let payloads = try NativeMessageFramer.extractMessages(
                    from: &connection.buffer
                )
                for payload in payloads {
                    let message = try BridgeMessageCodec.decode(payload)
                    guard message.direction == .extensionToNative else {
                        throw BridgeProtocolError.invalidSchema
                    }
                    events.append(
                        .message(connection: identifier, message: message)
                    )
                }
            } catch {
                events.append(.rejected(identifier))
                shouldDisconnect = true
            }

            if shouldDisconnect {
                Darwin.close(connection.fileDescriptor)
                connections.removeValue(forKey: identifier)
                events.append(.disconnected(identifier))
            } else {
                connections[identifier] = connection
            }
        }
        return events
    }

    public func send(
        _ message: BridgeMessage,
        to identifier: BridgeConnectionIdentifier
    ) throws {
        guard message.direction == .nativeToExtension else {
            throw BridgeProtocolError.invalidSchema
        }
        guard let connection = connections[identifier] else {
            throw LocalBridgeSocketError.connectionClosed
        }
        let payload = try BridgeMessageCodec.encode(message)
        try writeAll(
            try NativeMessageFramer.frame(payload),
            to: connection.fileDescriptor
        )
    }

    public func disconnect(_ identifier: BridgeConnectionIdentifier) {
        guard let connection = connections.removeValue(forKey: identifier) else {
            return
        }
        Darwin.close(connection.fileDescriptor)
    }
}

public final class LocalBridgeClient: @unchecked Sendable {
    let fileDescriptor: Int32
    private var buffer = Data()
    private var pendingMessages: [BridgeMessage] = []

    public init(
        socketURL: URL = StayPaneBridgeSocketLocation.defaultURL
    ) throws {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw LocalBridgeSocketError.systemCallFailed(errno)
        }
        do {
            try configureSocket(descriptor, nonblocking: false)
            try withSocketAddress(path: socketURL.path) { address, length in
                guard Darwin.connect(descriptor, address, length) == 0 else {
                    throw LocalBridgeSocketError.systemCallFailed(errno)
                }
            }
            fileDescriptor = descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    deinit {
        Darwin.close(fileDescriptor)
    }

    public func send(_ message: BridgeMessage) throws {
        guard message.direction == .extensionToNative else {
            throw BridgeProtocolError.invalidSchema
        }
        let payload = try BridgeMessageCodec.encode(message)
        try writeAll(
            try NativeMessageFramer.frame(payload),
            to: fileDescriptor
        )
    }

    public func readNextMessage() throws -> BridgeMessage? {
        while true {
            if !pendingMessages.isEmpty {
                return pendingMessages.removeFirst()
            }
            let payloads = try NativeMessageFramer.extractMessages(
                from: &buffer
            )
            for payload in payloads {
                pendingMessages.append(try decodeNativeMessage(payload))
            }
            if !pendingMessages.isEmpty {
                continue
            }
            var bytes = [UInt8](repeating: 0, count: 8_192)
            let count = Darwin.recv(fileDescriptor, &bytes, bytes.count, 0)
            if count > 0 {
                buffer.append(contentsOf: bytes.prefix(count))
                continue
            }
            if count == 0 {
                return nil
            }
            if errno == EINTR {
                continue
            }
            throw LocalBridgeSocketError.systemCallFailed(errno)
        }
    }

    public func finishSending() {
        _ = Darwin.shutdown(fileDescriptor, SHUT_WR)
    }

    func readAvailableMessages() throws -> (
        messages: [BridgeMessage],
        isClosed: Bool
    ) {
        var isClosed = false
        while true {
            var bytes = [UInt8](repeating: 0, count: 8_192)
            let count = Darwin.recv(
                fileDescriptor,
                &bytes,
                bytes.count,
                MSG_DONTWAIT
            )
            if count > 0 {
                buffer.append(contentsOf: bytes.prefix(count))
                continue
            }
            if count == 0 {
                isClosed = true
                break
            }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                break
            }
            if errno == EINTR {
                continue
            }
            throw LocalBridgeSocketError.systemCallFailed(errno)
        }
        let payloads = try NativeMessageFramer.extractMessages(from: &buffer)
        let messages = pendingMessages + (try payloads.map(decodeNativeMessage))
        pendingMessages = []
        return (messages, isClosed)
    }

    private func decodeNativeMessage(_ payload: Data) throws -> BridgeMessage {
        let message = try BridgeMessageCodec.decode(payload)
        guard message.direction == .nativeToExtension else {
            throw BridgeProtocolError.invalidSchema
        }
        return message
    }
}

private func configureSocket(
    _ fileDescriptor: Int32,
    nonblocking: Bool
) throws {
    var noSignal: Int32 = 1
    guard setsockopt(
        fileDescriptor,
        SOL_SOCKET,
        SO_NOSIGPIPE,
        &noSignal,
        socklen_t(MemoryLayout<Int32>.size)
    ) == 0 else {
        throw LocalBridgeSocketError.systemCallFailed(errno)
    }
    guard nonblocking else {
        return
    }
    let flags = fcntl(fileDescriptor, F_GETFL)
    guard flags >= 0,
          fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK) == 0
    else {
        throw LocalBridgeSocketError.systemCallFailed(errno)
    }
}

private func withSocketAddress<Result>(
    path: String,
    body: (UnsafePointer<sockaddr>, socklen_t) throws -> Result
) throws -> Result {
    var address = sockaddr_un()
    let pathBytes = path.utf8CString.map { UInt8(bitPattern: $0) }
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count <= capacity else {
        throw LocalBridgeSocketError.pathTooLong
    }
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
        destination.copyBytes(from: pathBytes)
    }
    let addressLength = MemoryLayout.offset(of: \sockaddr_un.sun_path)!
        + pathBytes.count
    address.sun_len = UInt8(addressLength)
    return try withUnsafePointer(to: &address) { pointer in
        try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            try body($0, socklen_t(addressLength))
        }
    }
}

private func writeAll(_ data: Data, to fileDescriptor: Int32) throws {
    try data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else {
            return
        }
        var offset = 0
        while offset < rawBuffer.count {
            let count = Darwin.send(
                fileDescriptor,
                baseAddress.advanced(by: offset),
                rawBuffer.count - offset,
                0
            )
            if count > 0 {
                offset += count
                continue
            }
            if count < 0, errno == EINTR {
                continue
            }
            throw LocalBridgeSocketError.systemCallFailed(errno)
        }
    }
}
