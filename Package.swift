// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Kotoverlay",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KotoverlayCore", targets: ["KotoverlayCore"]),
        .executable(name: "axprobe", targets: ["AXProbe"])
    ],
    targets: [
        .target(name: "KotoverlayCore"),
        .executableTarget(name: "AXProbe", dependencies: ["KotoverlayCore"]),
        .testTarget(name: "KotoverlayCoreTests", dependencies: ["KotoverlayCore"])
    ]
)
