// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NoSideMediaManager",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "NoSideMediaManager", targets: ["NoSideMediaManager"]),
        .library(name: "NoSideMediaCompanionCore", targets: ["NoSideMediaCompanionCore"]),
        .executable(name: "noside-media", targets: ["NoSideMediaCLI"]),
        .executable(name: "NoSideMediaManagerApp", targets: ["NoSideMediaManagerApp"])
    ],
    targets: [
        .target(name: "NoSideMediaManager"),
        .target(name: "NoSideMediaCompanionCore", dependencies: ["NoSideMediaManager"]),
        .executableTarget(name: "NoSideMediaCLI", dependencies: ["NoSideMediaManager"]),
        .executableTarget(name: "NoSideMediaManagerApp", dependencies: ["NoSideMediaManager", "NoSideMediaCompanionCore"]),
        .testTarget(name: "NoSideMediaManagerTests", dependencies: ["NoSideMediaManager", "NoSideMediaCompanionCore"])
    ]
)
