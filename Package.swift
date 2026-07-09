// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Junction",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "JunctionCore", targets: ["JunctionCore"]),
        .executable(name: "Junction", targets: ["JunctionApp"]),
        // Note: not named "junction" — APFS is case-insensitive, and a product named
        // "junction" would collide with the "Junction" app binary in .build/release.
        // The bundle script installs it as `junction` inside the app bundle.
        .executable(name: "junction-cli", targets: ["JunctionCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        // Pure-Foundation routing engine. No AppKit — unit-testable anywhere (incl. Linux CI).
        .target(
            name: "JunctionCore",
            resources: [
                .copy("Resources/rewriters.json"),
                .copy("Resources/tracking-params.json"),
            ]
        ),
        // macOS glue shared by the app and the CLI: dispatch, browser discovery, source-app resolution.
        .target(
            name: "JunctionMacKit",
            dependencies: ["JunctionCore"]
        ),
        .executableTarget(
            name: "JunctionApp",
            dependencies: ["JunctionCore", "JunctionMacKit"],
            resources: [
                .copy("Resources/starter-rules.json")
            ]
        ),
        .executableTarget(
            name: "JunctionCLI",
            dependencies: [
                "JunctionCore",
                "JunctionMacKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "JunctionCoreTests",
            dependencies: ["JunctionCore"]
        ),
    ]
)
