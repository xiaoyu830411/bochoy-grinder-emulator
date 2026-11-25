#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-debug}"
IDENTITY="${CODESIGN_IDENTITY:--}"

swift build --package-path "$ROOT" -c "$CONFIGURATION"
BINARY="$ROOT/.build/$CONFIGURATION/bochoy-grinder-emulator"
codesign --force --sign "$IDENTITY" "$BINARY"
codesign --verify --verbose=2 "$BINARY"
printf 'Signed simulator: %s\n' "$BINARY"
