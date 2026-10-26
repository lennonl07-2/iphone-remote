#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/iPhone Remote.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/build/module-cache"
xcrun swiftc -O -whole-module-optimization -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$ROOT/build/module-cache" "$ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/iPhoneRemote"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/Resources/Web" "$APP/Contents/Resources/"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"; fi
codesign --force --sign - --identifier local.iphoneremote.mac "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
