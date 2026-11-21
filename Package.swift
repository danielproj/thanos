// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Thanos",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Thanos",
            path: "Sources/Thanos",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ThanosTests",
            dependencies: ["Thanos"],
            path: "Tests/ThanosTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
