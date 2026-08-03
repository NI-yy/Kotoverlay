// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Kotoverlay",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KotoverlayCore", targets: ["KotoverlayCore"]),
        .executable(name: "axprobe", targets: ["AXProbe"]),
        .executable(name: "ocrprobe", targets: ["OCRProbe"]),
        .executable(name: "kotoverlay-cli", targets: ["KotoverlayCLI"])
    ],
    targets: [
        .target(name: "KotoverlayCore"),
        .executableTarget(name: "AXProbe", dependencies: ["KotoverlayCore"]),
        .executableTarget(name: "OCRProbe", dependencies: ["KotoverlayCore"]),
        .executableTarget(name: "KotoverlayCLI", dependencies: ["KotoverlayCore"]),
        .testTarget(name: "KotoverlayCoreTests", dependencies: ["KotoverlayCore"])
    ]
)
