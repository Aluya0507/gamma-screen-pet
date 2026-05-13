#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/Gamma.app"
CACHE="$ROOT/build/module-cache"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$CACHE"

CLANG_MODULE_CACHE_PATH="$CACHE" swiftc \
  -target arm64-apple-macosx13.0 \
  -Xcc -fmodules-cache-path="$CACHE" \
  "$ROOT/Sources/main.swift" \
  -framework AppKit \
  -o "$APP/Contents/MacOS/Gamma"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/Assets/frames" "$APP/Contents/Resources/frames"

chmod +x "$APP/Contents/MacOS/Gamma"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "$APP"
