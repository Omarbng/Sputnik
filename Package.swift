// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClipDock",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "ClipDock",
            path: "Sources/ClipDock"
        ),
    ]
)
