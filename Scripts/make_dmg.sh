#!/usr/bin/env bash
#
# Builds a Release .app and packages it into a styled DMG in dist/.
#
# Usage:
#   ./Scripts/make_dmg.sh
#   SKIP_BUILD=1 ./Scripts/make_dmg.sh     # reuse the existing Release build
#
# Requires: Xcode, xcodegen (for regenerating the project), create-dmg for the
# styled layout (falls back to a plain hdiutil image when unavailable).

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="Nami"
PROJECT="Nami.xcodeproj"
CONFIG="${CONFIG:-Release}"
DERIVED_DATA="${DERIVED_DATA:-build}"
APP_NAME="Nami"
VOLUME_NAME="Nami"
DIST_DIR="${DIST_DIR:-dist}"
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"
APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIG}/${APP_NAME}.app"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    if ! command -v xcodegen >/dev/null 2>&1; then
        echo "error: xcodegen not found (brew install xcodegen)" >&2
        exit 1
    fi
    if [[ ! -d "$PROJECT" || project.yml -nt "${PROJECT}/project.pbxproj" ]]; then
        echo "==> Generating ${PROJECT} from project.yml"
        xcodegen generate
    fi

    echo "==> Building ${APP_NAME} (${CONFIG})"
    BUILD_LOG="$(mktemp)"
    if ! xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -destination "platform=macOS" \
        -derivedDataPath "$DERIVED_DATA" \
        build >"$BUILD_LOG" 2>&1; then
        echo "error: build failed" >&2
        tail -40 "$BUILD_LOG" >&2
        rm -f "$BUILD_LOG"
        exit 1
    fi
    rm -f "$BUILD_LOG"
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: app not found at ${APP_PATH}" >&2
    exit 1
fi

mkdir -p "$DIST_DIR"

STAGE="$(mktemp -d)"
BACKGROUND="$(mktemp -d)/background.png"
cleanup() {
    hdiutil detach "/Volumes/${VOLUME_NAME}" -force -quiet >/dev/null 2>&1 || true
    rm -rf "$STAGE" "$(dirname "$BACKGROUND")"
}
trap cleanup EXIT

echo "==> Copying ${APP_NAME}.app into ${DIST_DIR}/"
rm -rf "${DIST_DIR}/${APP_NAME}.app"
ditto "$APP_PATH" "${DIST_DIR}/${APP_NAME}.app"
ditto "$APP_PATH" "${STAGE}/${APP_NAME}.app"

echo "==> Generating DMG background"
swift "Scripts/generate_dmg_background.swift" "$BACKGROUND" 660 420 >/dev/null

ICON="${APP_PATH}/Contents/Resources/AppIcon.icns"

echo "==> Creating ${DMG_PATH}"
rm -f "$DMG_PATH"
# A previously mounted copy would make create-dmg fail.
hdiutil detach "/Volumes/${VOLUME_NAME}" -force -quiet >/dev/null 2>&1 || true

CREATED=0
if command -v create-dmg >/dev/null 2>&1; then
    ICON_ARGS=()
    [[ -f "$ICON" ]] && ICON_ARGS=(--volicon "$ICON")

    if create-dmg \
        --volname "$VOLUME_NAME" \
        "${ICON_ARGS[@]}" \
        --background "$BACKGROUND" \
        --window-pos 200 120 \
        --window-size 660 420 \
        --text-size 13 \
        --icon-size 120 \
        --icon "${APP_NAME}.app" 175 200 \
        --hide-extension "${APP_NAME}.app" \
        --app-drop-link 485 200 \
        --no-internet-enable \
        --hdiutil-retries 10 \
        --format UDZO \
        "$DMG_PATH" "$STAGE"; then
        CREATED=1
    else
        echo "warning: create-dmg failed, falling back to a plain image" >&2
    fi
else
    echo "warning: create-dmg not found, falling back to a plain image" >&2
fi

if [[ "$CREATED" != "1" || ! -f "$DMG_PATH" ]]; then
    rm -f "$DMG_PATH"
    ditto "$APP_PATH" "${STAGE}/${APP_NAME}.app"
    ln -sfn /Applications "${STAGE}/Applications"
    hdiutil create \
        -volname "$VOLUME_NAME" \
        -srcfolder "$STAGE" \
        -ov -format UDZO \
        "$DMG_PATH"
fi

echo "==> Verifying"
hdiutil verify "$DMG_PATH" >/dev/null

echo
echo "Done:"
ls -lh "${DIST_DIR}/${APP_NAME}.app" "$DMG_PATH"
