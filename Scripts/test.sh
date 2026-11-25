#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift test --package-path "$ROOT"
node --test "$ROOT"/Scripts/web-tests/*.test.js
bash "$ROOT/Scripts/build.sh" debug
python3 "$ROOT/Scripts/smoke_test.py"
python3 "$ROOT/Scripts/web_smoke_test.py"
