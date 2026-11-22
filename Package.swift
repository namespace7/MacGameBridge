// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacGameBridge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacGameBridgeCore", targets: ["MacGameBridgeCore"]),
        .executable(name: "macgamebridge", targets: ["MacGameBridgeCLI"])
    ],
    targets: [
        .target(
            name: "MacGameBridgeCore",
            dependencies: [],
            path: "Sources/MacGameBridgeCore"
        ),
        .executableTarget(
            name: "MacGameBridgeCLI",
            dependencies: ["MacGameBridgeCore"],
            path: "Sources/MacGameBridgeCLI"
        ),
        .testTarget(
            name: "MacGameBridgeCoreTests",
            dependencies: ["MacGameBridgeCore"],
            path: "Tests/MacGameBridgeCoreTests"
        )
    ]
)
