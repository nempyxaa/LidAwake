// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LidAwake",
    platforms: [.macOS("14.4")],
    targets: [
        .target(name: "LidAwakeCore", path: "Sources/LidAwakeCore",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "LidAwake", dependencies: ["LidAwakeCore"], path: "Sources/LidAwake",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "LidAwakeTests", dependencies: ["LidAwakeCore", "LidAwake"], path: "Tests/LidAwakeTests",
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
