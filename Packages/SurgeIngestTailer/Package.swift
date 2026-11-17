// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SurgeIngestTailer",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SurgeIngestTailer", targets: ["SurgeIngestTailer"])],
    dependencies: [.package(path: "../SurgeCore")],
    targets: [
        .target(name: "SurgeIngestTailer", dependencies: [.product(name: "SurgeCore", package: "SurgeCore")]),
        .testTarget(name: "SurgeIngestTailerTests", dependencies: ["SurgeIngestTailer"]),
    ]
)
