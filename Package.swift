// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clawsy",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ClawsyMac", targets: ["ClawsyMac"]),
        .library(name: "ClawsyMacShare", type: .dynamic, targets: ["ClawsyMacShare"]),
        .library(name: "ClawsyFinderSync", type: .dynamic, targets: ["ClawsyFinderSync"]),
        .executable(name: "ScreenshotCLI", targets: ["ScreenshotCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.0.0")
    ],
    targets: [
        // Shared logic (macOS)
        .target(
            name: "ClawsyShared",
            dependencies: ["Starscream", "KeychainAccess"],
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
                .process("Assets.xcassets"),
                .process("Resources/en.lproj"),
                .process("Resources/de.lproj")
            ]
        ),

        // macOS Share Extension
        .target(
            name: "ClawsyMacShare",
            dependencies: ["ClawsyShared", "Starscream"],
            path: "Sources/ClawsyMacShare"
        ),

        // macOS FinderSync Extension
        .target(
            name: "ClawsyFinderSync",
            dependencies: ["ClawsyShared"],
            path: "Sources/ClawsyFinderSync",
            linkerSettings: [
                .linkedFramework("FinderSync")
            ]
        ),

        // Screenshot CLI — headless view rendering for marketing/docs
        .executableTarget(
            name: "ScreenshotCLI",
            dependencies: [],
            path: "Sources/ScreenshotCLI"
        )
    ]
)
