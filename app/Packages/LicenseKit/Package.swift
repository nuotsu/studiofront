// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LicenseKit",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "LicenseKit", targets: ["LicenseKit"]),
    ],
    targets: [
        .target(name: "LicenseKit"),
        .testTarget(
            name: "LicenseKitTests",
            dependencies: ["LicenseKit"]
        ),
    ]
)
