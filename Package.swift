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
            targets: ["GOFeatureFlag"])
    ],
    dependencies: [
        .package(url: "https://github.com/open-feature/swift-sdk.git", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "GOFeatureFlag",
            dependencies: [
                .product(name: "OpenFeature", package: "swift-sdk")
            ],
            plugins:[]
        ),
        .testTarget(
            name: "GOFeatureFlagTests",
            dependencies: [
                "GOFeatureFlag"
            ]
        )
    ]
)
