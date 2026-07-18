import Darwin
import Foundation
import StayPaneBridgeProtocol

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}

do {
    if CommandLine.arguments.dropFirst().first == "--register" {
        let executableURL = URL(
            fileURLWithPath: CommandLine.arguments[0]
        ).standardizedFileURL
        let manifestURL = try NativeMessagingHostInstaller().install(
            hostExecutableURL: executableURL
        )
        print(manifestURL.path)
    } else {
        guard let callerOrigin = CommandLine.arguments.dropFirst().first else {
            throw BridgeProtocolError.invalidSchema
        }
        try NativeMessagingHostRunner.run(callerOrigin: callerOrigin)
    }
} catch {
    writeError("StayPaneBridge: \(error.localizedDescription)")
    Darwin.exit(1)
}
