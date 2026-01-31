// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DroboBridge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DroboBridge", targets: ["DroboBridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "DroboBridge",
            dependencies: ["ZIPFoundation"],
            path: "Sources",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("DiskArbitration")
            ]
        ),
        .testTarget(
            name: "DroboBridgeTests",
            dependencies: ["DroboBridge"],
            path: "Tests"
        )
    ]
)
