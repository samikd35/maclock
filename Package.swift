// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StayPane",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "StayPaneCore", targets: ["StayPaneCore"]),
        .executable(name: "StayPane", targets: ["StayPane"])
    ],
    targets: [
        .target(name: "StayPaneCore"),
        .target(name: "StayPanePlatform"),
        .executableTarget(
            name: "StayPane",
            dependencies: ["StayPaneCore", "StayPanePlatform"]
        ),
        .testTarget(name: "StayPaneCoreTests", dependencies: ["StayPaneCore"]),
        .testTarget(
            name: "StayPanePlatformTests",
            dependencies: ["StayPanePlatform"]
        )
    ],
    swiftLanguageModes: [.v6]
)
