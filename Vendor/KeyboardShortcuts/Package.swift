// swift-tools-version:6.1
// Vendored copy of sindresorhus/KeyboardShortcuts 2.4.0 (MIT, see `license`).
// ClipDock's changes (search for "ClipDock patch" or see below):
// 1. Removed the three `#Preview` blocks at the end of Recorder.swift. The Previews macro
//    plugin ships only with Xcode, and ClipDock builds with the Command Line Tools.
// 2. Utilities.swift: localized strings load from `Contents/Resources/…bundle` first, because
//    SwiftPM's `Bundle.module` looks in the .app root, where codesign doesn't allow a bundle.
import PackageDescription

let package = Package(
	name: "KeyboardShortcuts",
	defaultLocalization: "en",
	platforms: [
		.macOS(.v10_15)
	],
	products: [
		.library(name: "KeyboardShortcuts", targets: ["KeyboardShortcuts"])
	],
	targets: [
		.target(
			name: "KeyboardShortcuts",
			swiftSettings: [
				.swiftLanguageMode(.v5)
			]
		)
	]
)
