#!/bin/bash
# Copies the build to /Applications and relaunches it.
set -euo pipefail
cd "$(dirname "$0")/.."
# Quit first so a running Prism never holds an event tap while signing or permissions change.
pkill -x Prism 2>/dev/null || true
bash scripts/build.sh
rm -rf /Applications/Prism.app
ditto build/Prism.app /Applications/Prism.app
open /Applications/Prism.app
echo "Installed /Applications/Prism.app"
