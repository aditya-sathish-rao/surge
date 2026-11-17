// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SurgeIngestProxy",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SurgeIngestProxy", targets: ["SurgeIngestProxy"])],
    dependencies: [.package(path: "../SurgeCore")],
    targets: [
        .target(name: "SurgeIngestProxy", dependencies: [.product(name: "SurgeCore", package: "SurgeCore")]),
        .testTarget(name: "SurgeIngestProxyTests", dependencies: ["SurgeIngestProxy"]),
    ]
)
