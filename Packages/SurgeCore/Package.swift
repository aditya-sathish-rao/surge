// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SurgeCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SurgeCore", targets: ["SurgeCore"])],
    targets: [
        .target(name: "SurgeCore", resources: [.process("Resources")]),
        .testTarget(name: "SurgeCoreTests", dependencies: ["SurgeCore"]),
    ]
)
