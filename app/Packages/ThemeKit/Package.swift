// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ThemeKit",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "ThemeKit", targets: ["ThemeKit"]),
    ],
    targets: [
        .target(name: "ThemeKit"),
    ]
)
