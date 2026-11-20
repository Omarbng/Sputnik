#!/bin/zsh
# Run unit tests (Swift Testing). Usage: scripts/test.sh [extra swift test args]
set -euo pipefail
cd "${0:A:h}/.."  # the project folder
source scripts/swiftpm-env.sh
swift test "${SWIFTPM_COMMON_FLAGS[@]}" "$@"
