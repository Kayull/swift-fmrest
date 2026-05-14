// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-fmrest",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "swift-fmrest",
            targets: ["swift-fmrest"]
        ),
    ],
    targets: [
        .target(
            name: "swift-fmrest"
        ),
        .testTarget(
            name: "swift-fmrestTests",
            dependencies: ["swift-fmrest"]
        ),
    ]
)
