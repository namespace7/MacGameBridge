// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacGameBridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "macgamebridge", targets: ["MacGameBridgeCLI"])
    ],
    targets: [
        .executableTarget(
            name: "MacGameBridgeCLI",
            path: "Sources/MacGameBridgeCLI"
        )
    ]
)
