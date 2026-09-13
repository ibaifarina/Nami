#!/usr/bin/env bash
#
# Builds a Release .app and copies it into dist/.
#
# Usage:
#   ./Scripts/make_app.sh
#   CONFIG=Debug ./Scripts/make_app.sh       # build a different configuration
#   SKIP_BUILD=1 ./Scripts/make_app.sh       # reuse the existing build
#
# Requires: Xcode, xcodegen (for regenerating the project).

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="Nami"
PROJECT="Nami.xcodeproj"
CONFIG="${CONFIG:-Release}"
DERIVED_DATA="${DERIVED_DATA:-build}"
APP_NAME="Nami"
DIST_DIR="${DIST_DIR:-dist}"
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

echo "==> Copying ${APP_NAME}.app into ${DIST_DIR}/"
rm -rf "${DIST_DIR}/${APP_NAME}.app"
ditto "$APP_PATH" "${DIST_DIR}/${APP_NAME}.app"

echo "==> Verifying"
codesign --verify --deep --strict "${DIST_DIR}/${APP_NAME}.app"

echo
echo "Done:"
ls -lh "${DIST_DIR}/${APP_NAME}.app"
