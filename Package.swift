// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AquaVoiceHook",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AquaVoiceHook",
            path: "Sources/AquaVoiceHook",
            exclude: ["Info.plist"]
        ),
    ]
)
