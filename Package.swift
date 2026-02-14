// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clawsy",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .executable(name: "ClawsyMac", targets: ["ClawsyMac"]),
        .library(name: "ClawsyShared", targets: ["ClawsyShared"]),
        .library(name: "ClawsyMacShare", type: .dynamic, targets: ["ClawsyMacShare"])
    ],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0")
    ],
    targets: [
        // Shared logic for all platforms
        .target(
            name: "ClawsyShared",
            dependencies: ["Starscream"],
            path: "Sources/ClawsyShared",
            resources: [
                .process("Resources/de.lproj"),
                .process("Resources/en.lproj"),
                .process("Resources/es.lproj"),
                .process("Resources/fr.lproj")
            ]
        ),
        
        // macOS App
        .executableTarget(
            name: "ClawsyMac",
            dependencies: ["ClawsyShared", "Starscream"],
            path: "Sources/ClawsyMac",
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        
        // macOS Share Extension
        .target(
            name: "ClawsyMacShare",
            dependencies: ["ClawsyShared", "Starscream"],
            path: "Sources/ClawsyMacShare"
        ),
        
        // iOS App Placeholder
        .target(
            name: "ClawsyIOS",
            dependencies: ["ClawsyShared"],
            path: "Sources/ClawsyIOS"
        ),
        
        // tvOS App Placeholder
        .target(
            name: "ClawsyTV",
            dependencies: ["ClawsyShared"],
            path: "Sources/ClawsyTV"
        ),
        
        // watchOS App Placeholder
        .target(
            name: "ClawsyWatch",
            dependencies: ["ClawsyShared"],
            path: "Sources/ClawsyWatch"
        )
    ]
)
