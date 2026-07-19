// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "converleon-conversion-core",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ConversionCore", targets: ["ConversionCore"]),
        .executable(name: "conversion-demo", targets: ["ConversionDemo"]),
    ],
    targets: [
        .target(name: "ConversionCore"),
        .executableTarget(name: "ConversionDemo", dependencies: ["ConversionCore"]),
        .testTarget(name: "ConversionCoreTests", dependencies: ["ConversionCore"]),
    ]
)
