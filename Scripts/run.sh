#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/Scripts/build.sh" debug
exec "$ROOT/.build/debug/bochoy-grinder-emulator" "$@"
