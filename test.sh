#!/bin/zsh
# Run unit tests (Swift Testing). Usage: ./test.sh [extra swift test args]
set -euo pipefail
cd "${0:A:h}"
source ./swiftpm-env.sh
swift test "${SWIFTPM_COMMON_FLAGS[@]}" "$@"
