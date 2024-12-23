// swift-tools-version: 5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GOFeatureFlag",
    platforms: [
        .iOS(.v14),
        .macOS(.v12)
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
        .package(url: "https://github.com/open-feature/swift-sdk.git", branch: "fatal-state"),
    ],
    targets: [
        .target(
            name: "OFREP",
            dependencies: [
                .product(name: "OpenFeature", package: "swift-sdk")
            ],
            plugins:[]
        ),
        .target(
            name: "GOFeatureFlag",
            dependencies: [
                "OFREP"
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
