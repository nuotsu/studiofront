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
    dependencies: [
        .package(path: "../SanityKit"),
        .package(path: "../StudioStore"),
    ],
    targets: [
        .target(
            name: "PresenceKit",
            dependencies: [
                .product(name: "SanityKit", package: "SanityKit"),
                .product(name: "StudioStore", package: "StudioStore"),
            ]
        ),
    ]
)
