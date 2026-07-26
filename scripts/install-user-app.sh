#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$REPOSITORY_ROOT/.build/StayPane.app"
DESTINATION="$HOME/Applications/StayPane.app"
SHOULD_BUILD=true
SHOULD_LAUNCH=true
SHOULD_REGISTER_CHROME=true
NATIVE_MANIFEST="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.staypane.native_bridge.json"

fail() {
    echo "StayPane installation failed: $1" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: install-user-app.sh [options]

Options:
  --source PATH       Install an already-built StayPane.app without rebuilding.
  --destination PATH  Install to an explicit StayPane.app path.
  --native-manifest PATH
                      Validate and roll back an explicit manifest path.
  --no-launch         Do not open StayPane after installation.
  --skip-chrome       Do not update Chrome Native Host Registration.
  --help              Show this help.
EOF
}

while (( $# > 0 )); do
    case "$1" in
    --source)
        (( $# >= 2 )) || fail "--source requires a path"
        SOURCE_APP="$2"
        SHOULD_BUILD=false
        shift 2
        ;;
    --destination)
        (( $# >= 2 )) || fail "--destination requires a path"
        DESTINATION="$2"
        shift 2
        ;;
    --native-manifest)
        (( $# >= 2 )) || fail "--native-manifest requires a path"
        NATIVE_MANIFEST="$2"
        shift 2
        ;;
    --no-launch)
        SHOULD_LAUNCH=false
        shift
        ;;
    --skip-chrome)
        SHOULD_REGISTER_CHROME=false
        shift
        ;;
    --help)
        usage
        exit 0
        ;;
    *)
        fail "unknown option: $1"
        ;;
    esac
done

[[ "$DESTINATION" == */StayPane.app ]] \
    || fail "destination must end with StayPane.app"
DESTINATION_PARENT="$(dirname "$DESTINATION")"
[[ "$DESTINATION_PARENT" != "/" ]] \
    || fail "refusing to install directly beneath the filesystem root"
if $SHOULD_REGISTER_CHROME; then
    [[ "$(basename "$NATIVE_MANIFEST")" == "com.staypane.native_bridge.json" ]] \
        || fail "Native Host manifest must use the fixed StayPane host name"
fi

mkdir -p "$DESTINATION_PARENT"
LOCK_FILE="$DESTINATION_PARENT/.staypane-install.lock"
LOCK_HELD=false

release_lock() {
    if $LOCK_HELD; then
        rm -f "$LOCK_FILE"
        LOCK_HELD=false
    fi
}
trap release_lock EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

shlock -p "$$" -f "$LOCK_FILE" \
    || fail "another StayPane installation is already in progress"
LOCK_HELD=true

assert_staypane_not_running() {
    if pgrep -x StayPane >/dev/null; then
        fail "StayPane is running. End any active Session, quit StayPane, and run make install again."
    fi
}

assert_staypane_not_running

if $SHOULD_BUILD; then
    make -C "$REPOSITORY_ROOT" app
fi

verify_bundle() {
    local app_path="$1"
    test -d "$app_path" \
        || fail "source app is missing: $app_path"
    test -x "$app_path/Contents/MacOS/StayPane" \
        || fail "StayPane executable is missing"
    test -x "$app_path/Contents/MacOS/StayPaneBridge" \
        || fail "StayPaneBridge executable is missing"
    test -f "$app_path/Contents/Resources/StayPane.icns" \
        || fail "StayPane application icon is missing"
    test -f "$app_path/Contents/Resources/ChromeExtension/manifest.json" \
        || fail "Chrome companion is missing"
    [[ "$(
        plutil -extract CFBundleIdentifier raw -o - \
            "$app_path/Contents/Info.plist"
    )" == "org.staypane.app" ]] \
        || fail "unexpected application bundle identifier"
    codesign --verify --strict "$app_path" \
        || fail "application signature verification failed"
}

verify_bundle "$SOURCE_APP"

WORK_DIRECTORY="$(
    mktemp -d "$DESTINATION_PARENT/.staypane-install.XXXXXX"
)"
STAGED_APP="$WORK_DIRECTORY/StayPane.app"
ATOMIC_SWAP="$WORK_DIRECTORY/atomic-swap"
MANIFEST_BACKUP="$WORK_DIRECTORY/native-manifest.json"
HAD_PREVIOUS_APP=false
HAD_NATIVE_MANIFEST=false
SWAP_STARTED=false
STAGED_INODE=""
CHROME_TOUCHED=false
COMMITTED=false

rollback() {
    if $COMMITTED; then
        rm -rf "$WORK_DIRECTORY"
        return
    fi

    if $CHROME_TOUCHED; then
        if $HAD_NATIVE_MANIFEST; then
            mkdir -p "$(dirname "$NATIVE_MANIFEST")"
            cp -p "$MANIFEST_BACKUP" "$NATIVE_MANIFEST"
        else
            rm -f "$NATIVE_MANIFEST"
        fi
    fi

    if $SWAP_STARTED; then
        local destination_inode=""
        if test -d "$DESTINATION"; then
            destination_inode="$(stat -f '%i' "$DESTINATION")"
        fi
        if [[ "$destination_inode" == "$STAGED_INODE" ]]; then
            if $HAD_PREVIOUS_APP && test -d "$STAGED_APP"; then
                "$ATOMIC_SWAP" "$STAGED_APP" "$DESTINATION"
            elif ! $HAD_PREVIOUS_APP; then
                rm -rf "$DESTINATION"
            fi
        fi
    fi

    rm -rf "$WORK_DIRECTORY"
}
cleanup() {
    rollback
    release_lock
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

swiftc "$REPOSITORY_ROOT/scripts/atomic-swap.swift" -o "$ATOMIC_SWAP"
ditto "$SOURCE_APP" "$STAGED_APP"
verify_bundle "$STAGED_APP"
assert_staypane_not_running
STAGED_INODE="$(stat -f '%i' "$STAGED_APP")"
SWAP_STARTED=true

if test -e "$DESTINATION"; then
    test -d "$DESTINATION" \
        || fail "destination exists and is not an application bundle"
    HAD_PREVIOUS_APP=true
    "$ATOMIC_SWAP" "$STAGED_APP" "$DESTINATION"
else
    mv "$STAGED_APP" "$DESTINATION"
fi

verify_bundle "$DESTINATION"

if $SHOULD_REGISTER_CHROME; then
    if test -f "$NATIVE_MANIFEST"; then
        HAD_NATIVE_MANIFEST=true
        cp -p "$NATIVE_MANIFEST" "$MANIFEST_BACKUP"
    fi
    CHROME_TOUCHED=true
    "$DESTINATION/Contents/MacOS/StayPaneBridge" \
        --register \
        --manifest-directory "$(dirname "$NATIVE_MANIFEST")" \
        >/dev/null

    EXPECTED_BRIDGE_DIRECTORY="$(
        cd "$DESTINATION/Contents/MacOS"
        pwd -L
    )"
    EXPECTED_BRIDGE="$EXPECTED_BRIDGE_DIRECTORY/StayPaneBridge"
    [[ "$(plutil -extract path raw -o - "$NATIVE_MANIFEST")" == "$EXPECTED_BRIDGE" ]] \
        || fail "Chrome registration does not point to the installed Native Bridge"
    [[ "$(
        plutil -extract allowed_origins.0 raw -o - "$NATIVE_MANIFEST"
    )" == "chrome-extension://hoofhoedlagpoclhkgnkmejaihaapoke/" ]] \
        || fail "Chrome registration permits an unexpected extension identity"
    [[ "$(stat -f '%Lp' "$NATIVE_MANIFEST")" == "600" ]] \
        || fail "Chrome registration permissions are not owner-only"
fi

COMMITTED=true
rm -rf "$WORK_DIRECTORY"
trap - EXIT INT TERM
release_lock

echo "Installed $DESTINATION"
if $SHOULD_REGISTER_CHROME; then
    echo "Registered the installed StayPane Native Bridge for Chrome."
fi

if $SHOULD_LAUNCH; then
    open "$DESTINATION"
fi
