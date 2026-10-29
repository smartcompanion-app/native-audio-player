// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SmartcompanionNativeAudioPlayer",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "SmartcompanionNativeAudioPlayer",
            targets: ["NativeAudioPlayerPlugin"])
    ],
    dependencies: [
        .package(name: "capacitor", path: "example/node_modules/@capacitor/ios")
    ],
    targets: [
        .target(
            name: "NativeAudioPlayerPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor")
            ],
            path: "ios/Sources/NativeAudioPlayerPlugin"),
        .testTarget(
            name: "NativeAudioPlayerPluginTests",
            dependencies: ["NativeAudioPlayerPlugin"],
            path: "ios/Tests/NativeAudioPlayerPluginTests")
    ]
)
