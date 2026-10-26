#!/bin/bash
# Packages the app into build/YunziiControl.dmg with a drag-to-Applications window.
# Usage: ./make_dmg.sh [path/to/YunziiControl.app]
#   default: build/YunziiControl.app if it exists, else /Applications/YunziiControl.app
# Needs dmgbuild: pip3 install dmgbuild   (uses $DMGBUILD_PYTHON, else ./.venv, else python3)
set -euo pipefail
cd "$(dirname "$0")"
DEFAULT_APP=build/YunziiControl.app
[ -d "$DEFAULT_APP" ] || DEFAULT_APP=/Applications/YunziiControl.app
APP="${1:-$DEFAULT_APP}"
PY="${DMGBUILD_PYTHON:-}"
[ -n "$PY" ] || { [ -x .venv/bin/python ] && PY=.venv/bin/python; } || true
[ -n "$PY" ] || PY=python3
"$PY" -c "import dmgbuild" 2>/dev/null || { echo "dmgbuild not found for $PY. Run: pip3 install dmgbuild" >&2; exit 1; }
mkdir -p build
rm -f build/YunziiControl.dmg
"$PY" -m dmgbuild -s dmg/settings.py -D app="$APP" -D here="$PWD/dmg" "Yunzii Control" build/YunziiControl.dmg
echo "Built build/YunziiControl.dmg"
