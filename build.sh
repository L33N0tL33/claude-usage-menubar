#!/bin/zsh
# Builds "Claude Usage.app" (a menu bar app, no Dock icon) and opens it.
#   ./build.sh                 -> installs to ~/Applications
#   OUT=/some/folder ./build.sh -> builds somewhere else (and does not launch it)
# Put your own logo.png next to this script to use it as the menu bar icon;
# without one, a plain bar-chart symbol is used.
set -e; cd "$(dirname "$0")"
DEST="${OUT:-$HOME/Applications}"
APP="$DEST/Claude Usage.app"
# when installing, quit a running copy first so the update really takes effect
if [ -z "$OUT" ]; then pkill -x ClaudeUsage 2>/dev/null || true; fi
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O main.swift -o "$APP/Contents/MacOS/ClaudeUsage"
cp Info.plist "$APP/Contents/Info.plist"
[ -f logo.png ] && cp logo.png "$APP/Contents/Resources/logo.png"
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "built $APP"
if [ -z "$OUT" ]; then open "$APP"; fi
