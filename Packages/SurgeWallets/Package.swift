// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SurgeWallets",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SurgeWallets", targets: ["SurgeWallets"])],
    dependencies: [.package(path: "../SurgeCore")],
    targets: [
        .target(name: "SurgeWallets", dependencies: [.product(name: "SurgeCore", package: "SurgeCore")]),
        .testTarget(name: "SurgeWalletsTests", dependencies: ["SurgeWallets"]),
    ]
)
