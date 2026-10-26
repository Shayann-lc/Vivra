// swift-tools-version: 6.2

import PackageDescription

// Platform-independent code. Must build and test on Linux as well as Apple
// platforms, so it may not depend on Apple-only frameworks except behind
// `#if canImport(...)`.
let package = Package(
    name: "VivraCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "VivraLogging", targets: ["VivraLogging"])
    ],
    targets: [
        .target(name: "VivraLogging"),
        .testTarget(name: "VivraLoggingTests", dependencies: ["VivraLogging"]),
    ],
    swiftLanguageModes: [.v6]
)
