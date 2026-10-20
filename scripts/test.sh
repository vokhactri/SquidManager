#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/env.sh
swift test "${TEST_FLAGS[@]}" "$@"
