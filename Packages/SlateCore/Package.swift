// swift-tools-version: 6.0

import PackageDescription

// Layer 1 — the domain core.
//
// This package MUST build and pass its tests on Linux. It has no dependencies,
// and it may import nothing but Foundation. Tools/check-layer-purity.sh
// enforces that mechanically in CI.
//
// `platforms:` does NOT make this package Apple-shaped, despite appearances.
// It sets minimum deployment targets used only when building for Apple
// platforms and is ignored entirely on Linux. Omitting it means SwiftPM falls
// back to macOS 10.13, which makes any standard-library API introduced in the
// last eight years an availability error — a trap that fires repeatedly and
// tempts exactly the wrong fix (sprinkling @available through the domain core).
let package = Package(
    name: "SlateCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SlateCore", targets: ["SlateCore"])
    ],
    targets: [
        .target(name: "SlateCore"),
        .testTarget(name: "SlateCoreTests", dependencies: ["SlateCore"])
    ]
)
