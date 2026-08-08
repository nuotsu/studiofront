// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SanityKit",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "SanityKit", targets: ["SanityKit"]),
    ],
    targets: [
        .target(name: "SanityKit"),
    ]
)
