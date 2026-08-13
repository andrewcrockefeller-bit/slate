// swift-tools-version: 6.0

import PackageDescription

// Layer 1 — the domain core.
//
// This package MUST build and pass its tests on Linux. It has no dependencies,
// and it may import nothing but Foundation. Tools/check-layer-purity.sh
// enforces that mechanically in CI; the absence of `platforms:` here is
// deliberate — declaring platforms would imply this package is Apple-shaped,
// and it is not.
let package = Package(
    name: "SlateCore",
    products: [
        .library(name: "SlateCore", targets: ["SlateCore"])
    ],
    targets: [
        .target(name: "SlateCore"),
        .testTarget(name: "SlateCoreTests", dependencies: ["SlateCore"])
    ]
)
