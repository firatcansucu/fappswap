// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fappswap",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "FappSwapCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "FappSwapApp",
            dependencies: ["FappSwapCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FappSwapCoreTests",
            dependencies: ["FappSwapCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
