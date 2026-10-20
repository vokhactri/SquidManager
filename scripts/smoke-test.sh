#!/bin/bash
# Opens build/SquidManager.app in the background for a few seconds and fails if it exits.
# Older SwiftPM versions look up resources by the absolute .build path of the machine that
# compiled the app, which hides a misplaced bundle there. Moving .build aside exposes it.
set -euo pipefail
cd "$(dirname "$0")/.."
mv .build .build-smoke
trap 'mv .build-smoke .build' EXIT

build/SquidManager.app/Contents/MacOS/SquidManager --background &
pid=$!
sleep 5
if ! kill -0 "$pid" 2>/dev/null; then
  status=0
  wait "$pid" || status=$?
  echo "SquidManager exited with status $status within 5 seconds" >&2
  exit 1
fi
kill "$pid"
echo "SquidManager ran for 5 seconds"
