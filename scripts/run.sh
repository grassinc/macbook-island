#!/bin/bash
# Build, then relaunch. Kills any running copy first so the panel does not
# get orphaned on screen by a rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh "${1:-debug}"
pkill -x Pill 2>/dev/null || true
open build/Pill.app
echo "==> launched (agent app: no Dock icon; look at the top of the screen)"
