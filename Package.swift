// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "api-key-lock",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "keylock", targets: ["keylock"]),
    ],
    targets: [
        .target(name: "KeylockCore"),
        .executableTarget(name: "keylock", dependencies: ["KeylockCore"]),
        .testTarget(name: "KeylockCoreTests", dependencies: ["KeylockCore"]),
    ]
)
