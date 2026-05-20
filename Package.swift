// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AquaVoiceHook",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
    ],
    targets: [
        .executableTarget(
            name: "AquaVoiceHook",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/AquaVoiceHook",
            exclude: ["Info.plist", "Entitlements.plist"]
        ),
    ]
)
