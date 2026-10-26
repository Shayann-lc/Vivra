// swift-tools-version: 6.2

import PackageDescription

// The HealthKit adapter. Apple platforms only; the sync logic it plugs into
// (SyncCore) is platform-independent and tested on Linux.
let package = Package(
    name: "HealthSync",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "HealthSync", targets: ["HealthSync"])
    ],
    dependencies: [
        .package(path: "../VivraCore")
    ],
    targets: [
        .target(
            name: "HealthSync",
            dependencies: [
                .product(name: "SyncCore", package: "VivraCore"),
                .product(name: "VivraModel", package: "VivraCore"),
                .product(name: "VivraLogging", package: "VivraCore"),
            ]
        ),
        .testTarget(
            name: "HealthSyncTests",
            dependencies: [
                "HealthSync",
                .product(name: "VivraModel", package: "VivraCore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
