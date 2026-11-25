// swift-tools-version: 6.3
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "bochoy-grinder-emulator",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "bochoy-grinder-emulator", targets: ["CrystalSim"]),
        .library(name: "CrystalWeb", targets: ["CrystalWeb"]),
    ],
    targets: [
        .target(name: "CrystalCore"),
        .target(
            name: "CrystalWeb",
            dependencies: ["CrystalCore"],
            resources: [.process("Web")]
        ),
        .executableTarget(
            name: "CrystalSim",
            dependencies: ["CrystalCore", "CrystalWeb"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "\(packageRoot)/Resources/Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "CrystalCoreTests",
            dependencies: ["CrystalCore"]
        ),
        .testTarget(
            name: "CrystalWebTests",
            dependencies: ["CrystalCore", "CrystalWeb"]
        )
    ]
)
