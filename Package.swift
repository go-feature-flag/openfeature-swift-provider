// swift-tools-version: 5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GOFeatureFlag",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .watchOS(.v8),
        .tvOS(.v15)
    ],
    products: [
        .library(
            name: "GOFeatureFlag",
            targets: ["GOFeatureFlag"]),
        .library(
            name: "OFREP",
            targets: ["OFREP"])
    ],
    dependencies: [
        .package(url: "https://github.com/open-feature/swift-sdk.git", .exact("0.6.0")),
        // Kept deliberately permissive so apps can pick the swift-log their toolchain
        // supports. Package.resolved pins 1.6.3 on purpose: it is the last release whose
        // manifest builds with Swift 5.9+, and newer ones require Swift 6.2 tools, which
        // the Swift 6.0 and 6.1 CI jobs cannot load. Do not bump the pin without checking.
        .package(url: "https://github.com/apple/swift-log", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "OFREP",
            dependencies: [
                .product(name: "OpenFeature", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log")
            ],
            plugins:[]
        ),
        .target(
            name: "GOFeatureFlag",
            dependencies: [
                "OFREP",
                .product(name: "OpenFeature", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log")
            ],
            plugins:[]
        ),
        .testTarget(
            name: "GOFeatureFlagTests",
            dependencies: [
                "GOFeatureFlag"
            ]
        ),
        .testTarget(
            name: "OFREPTests",
            dependencies: [
                "OFREP"
            ]
        )
    ]
)
