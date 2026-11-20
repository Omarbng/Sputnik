// swift-tools-version: 6.2
import PackageDescription

// Swift Testing ships with the Command Line Tools here, but without Xcode SwiftPM doesn't add
// it to the search paths (the compile-time -F is passed by scripts/run.sh and scripts/test.sh
// via scripts/swiftpm-env.sh).
// The CLT also lack the `_Testing_Foundation` module file, so cross-import overlays are
// turned off for the test target only.
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

let package = Package(
    name: "Sputnik",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.12.0"),
        .package(path: "Vendor/KeyboardShortcuts"),  // KeyboardShortcuts 2.4.0, vendored (see its Package.swift)
    ],
    targets: [
        // Pure logic + storage. No AppKit, so it's unit-testable.
        .target(
            name: "SputnikCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/SputnikCore"
        ),
        // The menu-bar app: AppKit/SwiftUI, pasteboard, windows.
        .executableTarget(
            name: "Sputnik",
            dependencies: [
                "SputnikCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/Sputnik",
            swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
        ),
        .testTarget(
            name: "SputnikCoreTests",
            dependencies: ["SputnikCore"],
            path: "Tests/SputnikCoreTests",
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-cross-import-overlays"]),
            ],
            linkerSettings: [
                .unsafeFlags(["-F", cltFrameworks, "-Xlinker", "-rpath", "-Xlinker", cltFrameworks]),
            ]
        ),
    ]
)
