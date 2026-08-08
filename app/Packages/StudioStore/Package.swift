// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "StudioStore",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "StudioStore", targets: ["StudioStore"]),
    ],
    targets: [
        .target(name: "StudioStore"),
    ]
)
