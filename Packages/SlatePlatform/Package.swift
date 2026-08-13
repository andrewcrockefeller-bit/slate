// swift-tools-version: 6.0

import PackageDescription

// Layer 2 — platform services.
//
// Thin adapters implementing protocols declared in SlateCore. This package is
// allowed to import UIKit, PencilKit, CloudKit, CoreGraphics, and anything else
// Apple ships; that is what it is for. It is NOT expected to build on Linux,
// and CI does not try.
//
// The one rule that matters here: nothing in this package may contain a
// decision. If an adapter starts branching on domain state, that logic belongs
// in SlateCore and the adapter should be handed the answer.
let package = Package(
    name: "SlatePlatform",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "SlatePlatform", targets: ["SlatePlatform"])
    ],
    dependencies: [
        .package(path: "../SlateCore")
    ],
    targets: [
        .target(
            name: "SlatePlatform",
            dependencies: ["SlateCore"]
        ),
        .testTarget(
            name: "SlatePlatformTests",
            dependencies: ["SlatePlatform", "SlateCore"]
        )
    ]
)
