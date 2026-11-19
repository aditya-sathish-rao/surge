// swift-tools-version: 6.0
import PackageDescription

// The widget extension has no test target of its own and the project files sit outside this
// target's boundary, so the widget's pure logic is tested through this package:
//
//     swift test --package-path Widget --scratch-path build/widget-tests
//
// Keep the scratch path under build/. It is gitignored and outside the paths `make lint` walks;
// the default Widget/.build would be picked up by that scan.
//
// The extension compiles the very same files from Widget/SurgeWidget/Logic.
let package = Package(
    name: "SurgeWidgetLogic",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../Packages/SurgeCore")],
    targets: [
        .target(
            name: "SurgeWidgetLogic",
            dependencies: [.product(name: "SurgeCore", package: "SurgeCore")],
            path: "SurgeWidget/Logic"
        ),
        .testTarget(
            name: "SurgeWidgetLogicTests",
            dependencies: ["SurgeWidgetLogic"],
            path: "SurgeWidgetTests"
        ),
    ]
)
