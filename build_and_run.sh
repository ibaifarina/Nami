#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

SCHEME="Nami"
PROJECT="Nami.xcodeproj"
CONFIG="${CONFIG:-Debug}"
DERIVED_DATA="build"
APP_NAME="Nami"
APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIG}/${APP_NAME}.app"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen not found (brew install xcodegen)" >&2
    exit 1
fi

if [ ! -d "$PROJECT" ] || [ project.yml -nt "${PROJECT}/project.pbxproj" ]; then
    echo "==> Generating ${PROJECT} from project.yml"
    xcodegen generate
fi

echo "==> Building ${SCHEME} (${CONFIG})"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    build

if [ ! -d "$APP_PATH" ]; then
    echo "error: build succeeded but ${APP_PATH} not found" >&2
    exit 1
fi

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "==> Quitting running ${APP_NAME}"
    osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || pkill -x "$APP_NAME" || true
    sleep 1
fi

echo "==> Launching ${APP_PATH}"
open "$APP_PATH"
