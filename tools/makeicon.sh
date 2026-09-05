#!/bin/bash
# Renders the app icon and packs it into Resources/AppIcon.icns.
# Usage: tools/makeicon.sh   (run from anywhere)
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=".build/icon"
mkdir -p "$WORK/AppIcon.iconset"
swiftc -O -o "$WORK/makeicon" tools/makeicon.swift
"$WORK/makeicon" "$WORK/icon-1024.png"

# iconutil wants these exact names and sizes.
for spec in 16:16 32:16@2x 32:32 64:32@2x 128:128 256:128@2x 256:256 512:256@2x 512:512 1024:512@2x; do
    px="${spec%%:*}"
    name="${spec##*:}"
    sips -z "$px" "$px" "$WORK/icon-1024.png" --out "$WORK/AppIcon.iconset/icon_${name}.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o Resources/AppIcon.icns
echo "[icon] wrote Resources/AppIcon.icns"
