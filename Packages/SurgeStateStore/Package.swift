// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SurgeStateStore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SurgeStateStore", targets: ["SurgeStateStore"])],
    dependencies: [.package(path: "../SurgeCore")],
    targets: [
        .target(name: "SurgeStateStore", dependencies: [.product(name: "SurgeCore", package: "SurgeCore")]),
        .testTarget(
            name: "SurgeStateStoreTests",
            dependencies: ["SurgeStateStore", .product(name: "SurgeCore", package: "SurgeCore")]
        ),
    ]
)
