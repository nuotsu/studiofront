// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PresenceKit",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "PresenceKit", targets: ["PresenceKit"]),
    ],
    targets: [
        .target(name: "PresenceKit"),
    ]
)
