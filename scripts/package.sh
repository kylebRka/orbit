#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh release
ditto -c -k --sequesterRsrc --keepParent dist/Orbit.app dist/Orbit-macOS.zip
echo "Packaged dist/Orbit-macOS.zip"
