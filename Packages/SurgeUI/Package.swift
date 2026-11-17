// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SurgeUI",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SurgeUI", targets: ["SurgeUI"])],
    dependencies: [.package(path: "../SurgeCore")],
    targets: [
        .target(name: "SurgeUI", dependencies: [.product(name: "SurgeCore", package: "SurgeCore")]),
        .testTarget(name: "SurgeUITests", dependencies: ["SurgeUI"]),
    ]
)
