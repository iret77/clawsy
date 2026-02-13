// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clawsy",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Clawsy", targets: ["Clawsy"])
    ],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Clawsy",
            dependencies: ["Starscream"],
            path: "Sources/Clawsy",
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ]
        )
    ]
)
