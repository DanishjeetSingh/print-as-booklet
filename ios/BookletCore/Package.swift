// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BookletCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "BookletCore", targets: ["BookletCore"]),
    ],
    targets: [
        .target(name: "BookletCore"),
        .testTarget(name: "BookletCoreTests", dependencies: ["BookletCore"]),
    ]
)
