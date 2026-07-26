#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_ICON="$REPOSITORY_ROOT/Resources/StayPaneIcon-1024.png"
BUILD_DIRECTORY="$REPOSITORY_ROOT/.build/app-icon"
ICONSET_DIRECTORY="$BUILD_DIRECTORY/StayPane.iconset"
OUTPUT_PATH="$BUILD_DIRECTORY/StayPane.icns"

fail() {
    echo "App icon build failed: $1" >&2
    exit 1
}

test -f "$SOURCE_ICON" || fail "1024px source icon is missing"
[[ "$(sips -g pixelWidth "$SOURCE_ICON" | awk '/pixelWidth/ {print $2}')" == "1024" ]] \
    || fail "source icon width must be 1024 pixels"
[[ "$(sips -g pixelHeight "$SOURCE_ICON" | awk '/pixelHeight/ {print $2}')" == "1024" ]] \
    || fail "source icon height must be 1024 pixels"

rm -rf "$ICONSET_DIRECTORY"
mkdir -p "$ICONSET_DIRECTORY"

render() {
    local size="$1"
    local name="$2"
    sips -z "$size" "$size" "$SOURCE_ICON" \
        --out "$ICONSET_DIRECTORY/$name" >/dev/null
}

render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil --convert icns \
    --output "$OUTPUT_PATH" \
    "$ICONSET_DIRECTORY"

test -f "$OUTPUT_PATH" || fail "iconutil did not create StayPane.icns"
echo "$OUTPUT_PATH"
