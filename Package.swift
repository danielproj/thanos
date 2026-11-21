// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Thanos",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Auto-update. Pinned exactly; bump deliberately and re-check the release signing steps.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "Thanos",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Thanos",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                // Sparkle.framework is embedded in Thanos.app/Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "ThanosTests",
            dependencies: ["Thanos"],
            path: "Tests/ThanosTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
