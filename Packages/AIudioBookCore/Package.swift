// swift-tools-version: 6.2
// AIudioBookCore — shared modules for the AIudioBook apps (macOS today, iOS later).
// Each feature lives in its own target so platform apps stay thin shells.

import PackageDescription

let package = Package(
    name: "AIudioBookCore",
    defaultLocalization: "en",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
    ],
    products: [
        // EPUBKit: parsing of EPUB files (container, package document, spine, TOC, cover).
        .library(name: "EPUBKit", targets: ["EPUBKit"]),
        // AIudioBookFeatures: umbrella product vending all feature modules to the apps.
        // Future feature targets (Reader, AI, TTS...) get appended here so the app
        // project never needs re-linking.
        .library(name: "AIudioBookFeatures", targets: ["LibraryFeature", "ReaderFeature"]),
    ],
    dependencies: [
        // ZIPFoundation: pure-Swift ZIP archive reading/writing (EPUB files are ZIP archives).
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "EPUBKit",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        .target(
            name: "LibraryFeature",
            dependencies: ["EPUBKit"],
            resources: [.process("Resources")],
            swiftSettings: [
                // UI-facing module: main-actor isolation by default, like the app target.
                .defaultIsolation(MainActor.self),
            ]
        ),
        .target(
            name: "ReaderFeature",
            dependencies: ["EPUBKit", "LibraryFeature"],
            resources: [.process("Resources")],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "EPUBKitTests",
            dependencies: [
                "EPUBKit",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
    ]
)
