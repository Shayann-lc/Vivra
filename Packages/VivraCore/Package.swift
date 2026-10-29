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
        .library(name: "VivraLogging", targets: ["VivraLogging"]),
        .library(name: "VivraModel", targets: ["VivraModel"]),
        .library(name: "SyncCore", targets: ["SyncCore"]),
        .library(name: "InsightEngine", targets: ["InsightEngine"]),
        .library(name: "NarrativeCore", targets: ["NarrativeCore"]),
        .library(name: "Gamification", targets: ["Gamification"]),
        .library(name: "Norms", targets: ["Norms"]),
        .library(name: "NarrativeEvals", targets: ["NarrativeEvals"]),
    ],
    targets: [
        .target(name: "VivraLogging"),
        .target(name: "VivraModel"),
        .target(name: "SyncCore", dependencies: ["VivraModel", "VivraLogging"]),
        .target(name: "InsightEngine", dependencies: ["VivraModel"]),
        .target(name: "NarrativeCore", dependencies: ["InsightEngine", "VivraModel", "VivraLogging"]),
        .target(name: "Gamification", dependencies: ["VivraModel"]),
        .target(name: "Norms", dependencies: ["InsightEngine", "NarrativeCore"]),
        // Fixed cases, scorers and reports for AI-written summaries (PLAN Phase 6).
        .target(name: "NarrativeEvals", dependencies: ["InsightEngine", "NarrativeCore", "SyncCore", "VivraModel"]),
        .testTarget(
            name: "NarrativeEvalsTests",
            dependencies: ["NarrativeEvals", "InsightEngine", "NarrativeCore", "VivraModel"]),
        .testTarget(name: "NormsTests", dependencies: ["Norms", "InsightEngine", "NarrativeCore"]),
        .testTarget(name: "GamificationTests", dependencies: ["Gamification", "VivraModel", "NarrativeCore"]),
        .testTarget(name: "VivraLoggingTests", dependencies: ["VivraLogging"]),
        .testTarget(name: "VivraModelTests", dependencies: ["VivraModel"]),
        .testTarget(name: "SyncCoreTests", dependencies: ["SyncCore", "VivraModel"]),
        .testTarget(name: "InsightEngineTests", dependencies: ["InsightEngine", "SyncCore", "VivraModel"]),
        .testTarget(name: "NarrativeCoreTests", dependencies: ["NarrativeCore", "InsightEngine", "VivraModel"]),
    ],
    swiftLanguageModes: [.v6]
)
