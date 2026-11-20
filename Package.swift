// swift-tools-version: 6.2
import PackageDescription

// Swift Testing ships with the Command Line Tools here, but without Xcode SwiftPM doesn't add
// it to the search paths (the compile-time -F is passed by run.sh/test.sh via swiftpm-env.sh).
// The CLT also lack the `_Testing_Foundation` module file, so cross-import overlays are
// turned off for the test target only.
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

let package = Package(
    name: "ClipDock",
    platforms: [.macOS(.v26)],
    products: [
        // The app is called Sputnik (renamed from ClipDock on 2026-11-20); the targets keep
        // their original names.
        .executable(name: "Sputnik", targets: ["ClipDock"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.12.0"),
        .package(path: "Vendor/KeyboardShortcuts"),  // KeyboardShortcuts 2.4.0, vendored (see its Package.swift)
    ],
    targets: [
        // Pure logic + storage. No AppKit, so it's unit-testable.
        .target(
            name: "ClipDockCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/ClipDockCore"
        ),
        // The menu-bar app: AppKit/SwiftUI, pasteboard, windows.
        .executableTarget(
            name: "ClipDock",
            dependencies: [
                "ClipDockCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/ClipDock",
            swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
        ),
        .testTarget(
            name: "ClipDockCoreTests",
            dependencies: ["ClipDockCore"],
            path: "Tests/ClipDockCoreTests",
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-cross-import-overlays"]),
            ],
            linkerSettings: [
                .unsafeFlags(["-F", cltFrameworks, "-Xlinker", "-rpath", "-Xlinker", cltFrameworks]),
            ]
        ),
    ]
)
