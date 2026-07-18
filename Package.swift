// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StayPane",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "StayPaneCore", targets: ["StayPaneCore"]),
        .library(
            name: "StayPaneBridgeProtocol",
            targets: ["StayPaneBridgeProtocol"]
        ),
        .executable(name: "StayPane", targets: ["StayPane"]),
        .executable(name: "StayPaneBridge", targets: ["StayPaneBridge"])
    ],
    targets: [
        .target(name: "StayPaneCore"),
        .target(name: "StayPaneBridgeProtocol"),
        .executableTarget(
            name: "StayPaneBridge",
            dependencies: ["StayPaneBridgeProtocol"]
        ),
        .target(name: "StayPanePlatform"),
        .executableTarget(
            name: "StayPane",
            dependencies: [
                "StayPaneCore",
                "StayPanePlatform",
                "StayPaneBridgeProtocol"
            ]
        ),
        .testTarget(name: "StayPaneCoreTests", dependencies: ["StayPaneCore"]),
        .testTarget(
            name: "StayPaneBridgeProtocolTests",
            dependencies: ["StayPaneBridgeProtocol"]
        ),
        .testTarget(
            name: "StayPanePlatformTests",
            dependencies: ["StayPanePlatform"]
        ),
        .testTarget(
            name: "StayPaneAppTests",
            dependencies: ["StayPane", "StayPaneBridgeProtocol"]
        )
    ],
    swiftLanguageModes: [.v6]
)
