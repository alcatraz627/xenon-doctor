#!/bin/bash
# Package XenonDoctor.app into a zip that can be AirDropped to the other Mac.
#
# The app is ad-hoc signed, not notarized. On the receiving Mac, unzip, drag the
# app to Applications, then right-click it and choose Open, then Open again at the
# prompt. That is a one-time step; afterwards it opens like any app.
set -euo pipefail
cd "$(dirname "$0")"

VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
APP="XenonDoctor.app"
ZIP="XenonDoctor-${VER}.zip"

./build.sh release

# ditto keeps the bundle's signature intact; plain zip can corrupt a .app.
rm -f "${ZIP}"
xattr -cr "${APP}"
ditto -c -k --keepParent --norsrc --noextattr "${APP}" "${ZIP}"
echo "[release] packaged ${ZIP}"
echo "[release] on the other Mac: unzip, move to /Applications, right-click, Open, Open"
