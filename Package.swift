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
        .package(url: "https://github.com/open-feature/swift-sdk.git", .exact("0.7.0")),
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
                "OFREP",
                .product(name: "OpenFeature", package: "swift-sdk")
            ],
            plugins:[]
        ),
        // Helpers shared by the two test targets. Not a product: it is only reachable from the
        // test targets, so it is never built for consumers of the package.
        .target(
            name: "TestSupport",
            dependencies: [
                .product(name: "OpenFeature", package: "swift-sdk")
            ],
            path: "Tests/TestSupport"
        ),
        .testTarget(
            name: "GOFeatureFlagTests",
            dependencies: [
                "GOFeatureFlag",
                "TestSupport"
            ]
        ),
        .testTarget(
            name: "OFREPTests",
            dependencies: [
                "OFREP",
                "TestSupport"
            ]
        )
    ]
)
