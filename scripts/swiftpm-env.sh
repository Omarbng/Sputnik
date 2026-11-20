# Shared SwiftPM settings for run.sh, test.sh and release.sh. Sourced, not executed.
# Identical flags in both scripts let them share one build cache without rebuilding.

# The project lives on the iCloud-synced Desktop. Keep build output outside it so iCloud
# doesn't upload it, evict it, or tag the bundle mid-codesign.
BUILD_ROOT="$HOME/Library/Caches/ClipDock-build"

# Without Xcode, SwiftPM doesn't search the Command Line Tools' framework folder, where
# Swift Testing lives. The generated test runner needs it to see `Testing`.
CLT_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

SWIFTPM_COMMON_FLAGS=(--scratch-path "$BUILD_ROOT/swiftpm" -Xswiftc -F -Xswiftc "$CLT_FRAMEWORKS")
