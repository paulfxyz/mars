// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mars",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "mars", targets: ["Mars"]),
        .executable(name: "mars-scan", targets: ["MarsScan"]),
        .library(name: "MarsCore", targets: ["MarsCore"])
    ],
    targets: [
        .target(name: "MarsCore"),
        .executableTarget(name: "Mars", dependencies: ["MarsCore"]),
        .executableTarget(name: "MarsScan", dependencies: ["MarsCore"]),
        .testTarget(name: "MarsCoreTests", dependencies: ["MarsCore"])
    ]
)
