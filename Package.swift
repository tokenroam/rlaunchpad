// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RLaunchPad",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RLaunchPad", targets: ["RLaunchPad"])
    ],
    targets: [
        .executableTarget(
            name: "RLaunchPad",
            path: "RLaunchPad",
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
