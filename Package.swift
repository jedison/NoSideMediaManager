// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NoSideMediaManager",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "NoSideMediaManager", targets: ["NoSideMediaManager"]),
        .executable(name: "noside-media", targets: ["NoSideMediaCLI"]),
        .executable(name: "NoSideMediaManagerApp", targets: ["NoSideMediaManagerApp"])
    ],
    targets: [
        .target(name: "NoSideMediaManager"),
        .executableTarget(name: "NoSideMediaCLI", dependencies: ["NoSideMediaManager"]),
        .executableTarget(name: "NoSideMediaManagerApp", dependencies: ["NoSideMediaManager"]),
        .testTarget(name: "NoSideMediaManagerTests", dependencies: ["NoSideMediaManager"])
    ]
)
