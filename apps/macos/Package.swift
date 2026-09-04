// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WatchBridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WatchBridge", targets: ["WatchBridge"]),
    ],
    targets: [
        .systemLibrary(
            name: "CWatchBridge",
            path: "Sources/CWatchBridge"
        ),
        .executableTarget(
            name: "WatchBridge",
            dependencies: ["CWatchBridge"],
            path: "Sources/WatchBridge",
            linkerSettings: [
                .unsafeFlags(["-L", "Libraries", "-lwatchbridge_core"]),
            ]
        ),
        .testTarget(
            name: "WatchBridgeTests",
            dependencies: ["WatchBridge"],
            path: "Tests/WatchBridgeTests"
        ),
    ]
)
