#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/staypane-release.XXXXXX")"
trap 'rm -rf "$LOG_DIRECTORY"' EXIT

fail() {
    echo "Release Verification failed: $1" >&2
    exit 1
}

for required_tool in \
    bash \
    codesign \
    git \
    iconutil \
    lipo \
    make \
    node \
    npm \
    otool \
    plutil \
    sips \
    shlock \
    swift \
    swiftc
do
    command -v "$required_tool" >/dev/null \
        || fail "required tool is unavailable: $required_tool"
done

[[ "$(uname -m)" == "arm64" ]] \
    || fail "v1 verification requires an Apple-silicon Mac"
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[[ "$MACOS_MAJOR" =~ ^[0-9]+$ ]] \
    || fail "could not determine the macOS version"
(( MACOS_MAJOR >= 26 )) \
    || fail "v1 verification requires macOS 26 or newer"

redact_log() {
    bash "$REPOSITORY_ROOT/scripts/redact-release-log.sh" \
        "$REPOSITORY_ROOT" \
        "$HOME"
}

run_step() {
    local label="$1"
    shift
    local log_path="$LOG_DIRECTORY/$(echo "$label" | tr '[:upper:] ' '[:lower:]-').log"
    if (cd "$REPOSITORY_ROOT" && "$@") >"$log_path" 2>&1; then
        echo "PASS: $label"
        return
    fi

    echo "FAIL: $label" >&2
    tail -n 200 "$log_path" | redact_log >&2
    exit 1
}

run_step "Release contract" make test-release
run_step "Swift app, engine, bridge, and privacy tests" make test
run_step "Chrome companion tests" make test-extension
run_step "Release app and Native Bridge build" make app
run_step "Hermetic local install" make test-install
run_step "Packaged source release audit" \
    bash scripts/audit-source-release.sh

echo "StayPane Release Verification passed."
