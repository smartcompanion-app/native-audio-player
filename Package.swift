// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NativeAudioPlayer",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "NativeAudioPlayer",
            targets: ["NativeAudioPlayerPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "NativeAudioPlayerPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/NativeAudioPlayerPlugin"),
        .testTarget(
            name: "NativeAudioPlayerPluginTests",
            dependencies: ["NativeAudioPlayerPlugin"],
            path: "ios/Tests/NativeAudioPlayerPluginTests")
    ]
)