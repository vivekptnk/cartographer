// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Cartographer",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Cartographer",
            targets: ["Cartographer"]
        )
    ],
    targets: [
        .target(
            name: "Cartographer",
            path: "Sources/Cartographer",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "CartographerTests",
            dependencies: ["Cartographer"],
            path: "Tests/CartographerTests"
        )
    ]
)
