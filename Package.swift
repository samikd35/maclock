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
        .executableTarget(name: "StayPane", dependencies: ["StayPaneCore"]),
        .testTarget(name: "StayPaneCoreTests", dependencies: ["StayPaneCore"])
    ],
    swiftLanguageModes: [.v6]
)
