#!/bin/bash

set -euo pipefail

SOURCE_ONLY=false
if [[ "${1:-}" == "--source-only" ]]; then
    SOURCE_ONLY=true
    shift
fi

REPOSITORY_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
REPOSITORY_ROOT="$(cd "$REPOSITORY_ROOT" && pwd)"

fail() {
    echo "Source release audit failed: $1" >&2
    exit 1
}

require_file() {
    test -f "$REPOSITORY_ROOT/$1" || fail "required file is missing: $1"
}

require_text() {
    local path="$1"
    local text="$2"
    grep -Fiq "$text" "$REPOSITORY_ROOT/$path" \
        || fail "$path is missing a required release statement"
}

for required_path in \
    LICENSE \
    README.md \
    ROADMAP.md \
    .node-version \
    CONTEXT-MAP.md \
    Package.swift \
    Resources/StayPane-Info.plist \
    ChromeExtension/manifest.json \
    ChromeExtension/package.json \
    docs/INSTALL.md \
    docs/manual-testing/v1-release-matrix.md \
    docs/contexts/product/CONTEXT.md \
    docs/contexts/macos/CONTEXT.md \
    docs/contexts/chrome/CONTEXT.md \
    docs/contexts/native-bridge/CONTEXT.md
do
    require_file "$required_path"
done

require_text LICENSE "MIT License"
require_text LICENSE "Permission is hereby granted, free of charge"
require_text README.md "commercial and closed-source reuse"
require_text docs/INSTALL.md "unsigned source distribution"
require_text docs/INSTALL.md "no paid Apple or Google developer account"
require_text docs/INSTALL.md "local-only"
require_text docs/INSTALL.md "honest self-control tool"
require_text ROADMAP.md "Safari first"
require_text ROADMAP.md "other Chromium browsers next"
require_text ROADMAP.md "Firefox afterward"

MINIMUM_SYSTEM_VERSION="$(
    plutil -extract LSMinimumSystemVersion raw -o - \
        "$REPOSITORY_ROOT/Resources/StayPane-Info.plist"
)"
[[ "$MINIMUM_SYSTEM_VERSION" == "26.0" ]] \
    || fail "Info.plist must declare macOS 26.0 as the minimum"

node - "$REPOSITORY_ROOT" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const root = process.argv[2];
const manifest = JSON.parse(
  fs.readFileSync(path.join(root, "ChromeExtension/manifest.json"), "utf8"),
);
const packageJSON = JSON.parse(
  fs.readFileSync(path.join(root, "ChromeExtension/package.json"), "utf8"),
);
const expectedPermissions = [
  "favicon",
  "nativeMessaging",
  "storage",
  "tabs",
  "webNavigation",
];
const actualPermissions = [...(manifest.permissions ?? [])].sort();
if (JSON.stringify(actualPermissions) !== JSON.stringify(expectedPermissions)) {
  throw new Error("Chrome permissions differ from the reviewed v1 set");
}
if (manifest.host_permissions !== undefined ||
    manifest.optional_host_permissions !== undefined ||
    manifest.update_url !== undefined) {
  throw new Error("Chrome manifest introduces remote hosts or automatic updates");
}
if (manifest.manifest_version !== 3 || packageJSON.private !== true) {
  throw new Error("Chrome release metadata is not source-only Manifest V3");
}
if (packageJSON.engines?.node !== ">=20") {
  throw new Error("Chrome release metadata does not declare Node.js 20+");
}
NODE

FORBIDDEN_RUNTIME_PATTERN='URLSession|URLSessionConfiguration|NWConnection|NWTCPConnection|XMLHttpRequest|WebSocket|EventSource|SentrySDK|Sparkle|SUUpdater|SCScreenshotManager|SCStream|CGDisplayStream|CGWindowListCreateImage|PrivateFrameworks|dlopen[[:space:]]*\(|dlsym[[:space:]]*\('
while IFS= read -r -d '' source_path; do
    if grep -Eq "$FORBIDDEN_RUNTIME_PATTERN" "$source_path"; then
        fail "runtime source introduces an unreviewed network, updater, capture, telemetry, or private-framework API"
    fi
done < <(
    find \
        "$REPOSITORY_ROOT/Sources" \
        "$REPOSITORY_ROOT/ChromeExtension/src" \
        -type f \( -name '*.swift' -o -name '*.ts' \) -print0
)

if [[ "$SOURCE_ONLY" == true ]]; then
    echo "Source release audit passed."
    exit 0
fi

APP_PATH="$REPOSITORY_ROOT/.build/StayPane.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/StayPane"
BRIDGE_EXECUTABLE="$APP_PATH/Contents/MacOS/StayPaneBridge"
PACKAGED_MANIFEST="$APP_PATH/Contents/Resources/ChromeExtension/manifest.json"

test -d "$APP_PATH" || fail "packaged StayPane.app is missing"
test -x "$APP_EXECUTABLE" || fail "packaged StayPane executable is missing"
test -x "$BRIDGE_EXECUTABLE" || fail "packaged Native Bridge is missing"
test -f "$PACKAGED_MANIFEST" || fail "packaged Chrome companion is missing"

codesign --verify --strict "$APP_PATH" \
    || fail "packaged app does not pass code-signature verification"
SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
grep -Fq "Signature=adhoc" <<<"$SIGNATURE_DETAILS" \
    || fail "packaged app is not locally ad-hoc signed"
if grep -Fq "Authority=" <<<"$SIGNATURE_DETAILS"; then
    fail "packaged app unexpectedly carries a signing authority"
fi

for executable_path in "$APP_EXECUTABLE" "$BRIDGE_EXECUTABLE"; do
    lipo -archs "$executable_path" | grep -Eq '(^|[[:space:]])arm64($|[[:space:]])' \
        || fail "packaged executable is missing Apple-silicon architecture"
    if otool -L "$executable_path" | grep -Fq '/PrivateFrameworks/'; then
        fail "packaged executable links a private macOS framework"
    fi
done

cmp -s "$REPOSITORY_ROOT/ChromeExtension/manifest.json" "$PACKAGED_MANIFEST" \
    || fail "packaged Chrome manifest differs from the reviewed source manifest"

PACKAGED_MINIMUM_SYSTEM_VERSION="$(
    plutil -extract LSMinimumSystemVersion raw -o - \
        "$APP_PATH/Contents/Info.plist"
)"
[[ "$PACKAGED_MINIMUM_SYSTEM_VERSION" == "26.0" ]] \
    || fail "packaged app does not require macOS 26.0"

echo "Packaged source release audit passed."
