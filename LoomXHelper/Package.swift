// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LoomXHelper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LoomXHelper", targets: ["LoomXHelper"])
    ],
    targets: [
        .executableTarget(name: "LoomXHelper")
    ]
)
