#!/bin/bash
# Build XenonDoctor.app from the SwiftPM workspace.
#
# SPM emits a bare executable. A menu bar app needs a real .app bundle so
# LSUIElement is honoured and the Bluetooth usage string is read. This wraps the
# binary into Contents/MacOS plus Contents/Info.plist and ad-hoc signs it so a
# quarantined copy on another Mac still launches after one right-click Open.
#
# Usage:
#   ./build.sh            release build, assembles ./XenonDoctor.app
#   ./build.sh debug      debug build
#   ./build.sh --run      build then open the app
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="XenonDoctor"
APP_DIR="${APP_NAME}.app"
CONFIG="release"
RUN_AFTER=0
for arg in "$@"; do
    case "$arg" in
        debug)   CONFIG="debug" ;;
        release) CONFIG="release" ;;
        --run)   RUN_AFTER=1 ;;
        *) echo "Unknown arg: $arg"; exit 2 ;;
    esac
done

echo "[build] Compiling ${APP_NAME} (${CONFIG})"
swift build -c "${CONFIG}" --product "${APP_NAME}"

BIN_PATH=".build/${CONFIG}/${APP_NAME}"
test -x "${BIN_PATH}" || { echo "[build] FAIL: expected binary missing: ${BIN_PATH}"; exit 1; }

echo "[build] Assembling ${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
cp -f "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp -f Resources/Info.plist "${APP_DIR}/Contents/Info.plist"
cp -f Resources/com.xenondoctor.steam-env.plist "${APP_DIR}/Contents/Resources/com.xenondoctor.steam-env.plist"
cp -f Resources/pads.json "${APP_DIR}/Contents/Resources/pads.json"
if [[ -f Resources/AppIcon.icns ]]; then
    cp -f Resources/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc sign so macOS does not refuse to launch an unsigned, quarantined bundle.
codesign --force --sign - "${APP_DIR}" >/dev/null 2>&1 || true

echo "[build] OK -> ${APP_DIR}"

if [[ "${RUN_AFTER}" -eq 1 ]]; then
    pkill -f "${APP_DIR}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
    sleep 0.3
    open "${APP_DIR}"
fi
