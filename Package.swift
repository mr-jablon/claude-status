// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudeStatus",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeStatus", targets: ["ClaudeStatus"]),
    ],
    targets: [
        .target(name: "ClaudeStatusCore"),
        .executableTarget(name: "ClaudeStatus", dependencies: ["ClaudeStatusCore"]),
        .testTarget(
            name: "ClaudeStatusCoreTests",
            dependencies: ["ClaudeStatusCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
