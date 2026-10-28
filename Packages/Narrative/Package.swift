// swift-tools-version: 6.2

import PackageDescription

// The on-device Foundation Models narrator. Apple platforms only; the rules
// it must follow (validator, templates, prompts) live in NarrativeCore and
// are tested on Linux.
let package = Package(
    name: "Narrative",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "Narrative", targets: ["Narrative"]),
        // Live evals of the on-device model on a Mac with Apple Intelligence
        // (PLAN Phase 6): swift run --package-path Packages/Narrative vivra-evals
        .executable(name: "vivra-evals", targets: ["VivraEvals"]),
    ],
    dependencies: [
        .package(path: "../VivraCore")
    ],
    targets: [
        .target(
            name: "Narrative",
            dependencies: [
                .product(name: "NarrativeCore", package: "VivraCore"),
                .product(name: "InsightEngine", package: "VivraCore"),
            ]
        ),
        .executableTarget(
            name: "VivraEvals",
            dependencies: [
                "Narrative",
                .product(name: "NarrativeEvals", package: "VivraCore"),
                .product(name: "NarrativeCore", package: "VivraCore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
