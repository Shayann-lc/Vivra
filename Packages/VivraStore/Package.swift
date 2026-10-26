// swift-tools-version: 6.2

import PackageDescription

// The encrypted on-device store. Apple platforms only: it links SQLCipher
// (an XCFramework) through the vendored GRDB in Vendor/GRDB.
let package = Package(
    name: "VivraStore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "VivraStore", targets: ["VivraStore"])
    ],
    dependencies: [
        .package(path: "../VivraCore"),
        .package(path: "../../Vendor/GRDB"),
    ],
    targets: [
        .target(
            name: "VivraStore",
            dependencies: [
                .product(name: "VivraLogging", package: "VivraCore"),
                .product(name: "GRDB", package: "GRDB"),
            ]
        ),
        .testTarget(name: "VivraStoreTests", dependencies: ["VivraStore"]),
    ],
    swiftLanguageModes: [.v6]
)
