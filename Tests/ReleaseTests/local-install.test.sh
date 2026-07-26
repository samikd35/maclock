#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_APP="$REPOSITORY_ROOT/.build/StayPane.app"
INSTALLER="$REPOSITORY_ROOT/scripts/install-user-app.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/staypane-install-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "Local install test failed: $1" >&2
    exit 1
}

test -d "$SOURCE_APP" || fail "packaged source app is missing"
test -x "$INSTALLER" || fail "installer is missing or not executable"

DESTINATION="$TEST_ROOT/Applications/StayPane.app"
TEST_NATIVE_MANIFEST="$TEST_ROOT/NativeMessagingHosts/com.staypane.native_bridge.json"
REAL_NATIVE_MANIFEST="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.staypane.native_bridge.json"
REAL_MANIFEST_BACKUP="$TEST_ROOT/real-native-manifest.json"
HAD_REAL_MANIFEST=false
if test -f "$REAL_NATIVE_MANIFEST"; then
    HAD_REAL_MANIFEST=true
    cp -p "$REAL_NATIVE_MANIFEST" "$REAL_MANIFEST_BACKUP"
fi
TEST_HOME="$TEST_ROOT/Home"
USER_DATA_DIRECTORY="$TEST_HOME/Library/Application Support/StayPane"
PREFERENCES_DIRECTORY="$TEST_HOME/Library/Preferences"
mkdir -p "$USER_DATA_DIRECTORY" "$PREFERENCES_DIRECTORY"
printf '%s' 'recovery-sentinel' \
    >"$USER_DATA_DIRECTORY/active-session.json"
printf '%s' 'history-sentinel' \
    >"$USER_DATA_DIRECTORY/session-history.json"
printf '%s' 'preferences-sentinel' \
    >"$PREFERENCES_DIRECTORY/org.staypane.app.plist"
RECOVERY_HASH="$(
    shasum -a 256 "$USER_DATA_DIRECTORY/active-session.json"
)"
HISTORY_HASH="$(
    shasum -a 256 "$USER_DATA_DIRECTORY/session-history.json"
)"
PREFERENCES_HASH="$(
    shasum -a 256 "$PREFERENCES_DIRECTORY/org.staypane.app.plist"
)"
export HOME="$TEST_HOME"

"$INSTALLER" \
    --source "$SOURCE_APP" \
    --destination "$DESTINATION" \
    --native-manifest "$TEST_NATIVE_MANIFEST" \
    --no-launch

test -x "$DESTINATION/Contents/MacOS/StayPane" \
    || fail "installed app executable is missing"
test -x "$DESTINATION/Contents/MacOS/StayPaneBridge" \
    || fail "installed Native Bridge is missing"
test -f "$DESTINATION/Contents/Resources/StayPane.icns" \
    || fail "installed app icon is missing"
codesign --verify --strict "$DESTINATION" \
    || fail "installed app signature is invalid"
EXPECTED_TEST_BRIDGE_DIRECTORY="$(
    cd "$DESTINATION/Contents/MacOS"
    pwd -L
)"
[[ "$(
    plutil -extract path raw -o - "$TEST_NATIVE_MANIFEST"
)" == "$EXPECTED_TEST_BRIDGE_DIRECTORY/StayPaneBridge" ]] \
    || fail "hermetic Chrome registration does not name the installed bridge"
if $HAD_REAL_MANIFEST; then
    cmp -s "$REAL_MANIFEST_BACKUP" "$REAL_NATIVE_MANIFEST" \
        || fail "hermetic registration changed the real Chrome manifest"
else
    test ! -e "$REAL_NATIVE_MANIFEST" \
        || fail "hermetic registration created the real Chrome manifest"
fi

FIRST_INSTALL_HASH="$(shasum -a 256 "$DESTINATION/Contents/MacOS/StayPane")"
FIRST_BRIDGE_HASH="$(
    shasum -a 256 "$DESTINATION/Contents/MacOS/StayPaneBridge"
)"

"$INSTALLER" \
    --source "$SOURCE_APP" \
    --destination "$DESTINATION" \
    --no-launch \
    --skip-chrome

SECOND_INSTALL_HASH="$(shasum -a 256 "$DESTINATION/Contents/MacOS/StayPane")"
[[ "$FIRST_INSTALL_HASH" == "$SECOND_INSTALL_HASH" ]] \
    || fail "reinstallation did not preserve the verified app payload"

FAILING_SOURCE="$TEST_ROOT/Failing-Registration.app"
ditto "$SOURCE_APP" "$FAILING_SOURCE"
printf '#!/bin/sh\nexit 1\n' \
    >"$FAILING_SOURCE/Contents/MacOS/StayPaneBridge"
chmod 755 "$FAILING_SOURCE/Contents/MacOS/StayPaneBridge"
codesign --force --sign - --timestamp=none \
    "$FAILING_SOURCE/Contents/MacOS/StayPaneBridge" >/dev/null
codesign --force --sign - --timestamp=none "$FAILING_SOURCE" >/dev/null

if "$INSTALLER" \
    --source "$FAILING_SOURCE" \
    --destination "$DESTINATION" \
    --native-manifest "$TEST_ROOT/NativeMessagingHosts/com.staypane.native_bridge.json" \
    --no-launch
then
    fail "installer accepted a failed post-swap Chrome registration"
fi

AFTER_ROLLBACK_HASH="$(shasum -a 256 "$DESTINATION/Contents/MacOS/StayPane")"
[[ "$FIRST_INSTALL_HASH" == "$AFTER_ROLLBACK_HASH" ]] \
    || fail "post-swap failure did not restore the previous app"
AFTER_ROLLBACK_BRIDGE_HASH="$(
    shasum -a 256 "$DESTINATION/Contents/MacOS/StayPaneBridge"
)"
[[ "$FIRST_BRIDGE_HASH" == "$AFTER_ROLLBACK_BRIDGE_HASH" ]] \
    || fail "post-swap failure did not atomically restore the previous bridge"
codesign --verify --strict "$DESTINATION" \
    || fail "post-swap rollback did not restore the previous signature"

INVALID_SOURCE="$TEST_ROOT/Invalid.app"
ditto "$SOURCE_APP" "$INVALID_SOURCE"
rm "$INVALID_SOURCE/Contents/MacOS/StayPane"

if "$INSTALLER" \
    --source "$INVALID_SOURCE" \
    --destination "$DESTINATION" \
    --no-launch \
    --skip-chrome
then
    fail "installer accepted an invalid source bundle"
fi

test -x "$DESTINATION/Contents/MacOS/StayPane" \
    || fail "failed update damaged the previous installation"
codesign --verify --strict "$DESTINATION" \
    || fail "failed update damaged the previous signature"

FAKE_BIN="$TEST_ROOT/fake-bin"
mkdir -p "$FAKE_BIN"
printf '#!/bin/sh\nexit 0\n' >"$FAKE_BIN/pgrep"
chmod 755 "$FAKE_BIN/pgrep"

if PATH="$FAKE_BIN:$PATH" "$INSTALLER" \
    --source "$SOURCE_APP" \
    --destination "$DESTINATION" \
    --no-launch \
    --skip-chrome
then
    fail "installer did not refuse an update while StayPane was running"
fi

SEQUENTIAL_FAKE_BIN="$TEST_ROOT/sequential-fake-bin"
SEQUENTIAL_PGREP_COUNT="$TEST_ROOT/sequential-pgrep-count"
mkdir -p "$SEQUENTIAL_FAKE_BIN"
printf '%s\n' \
    '#!/bin/sh' \
    'count=0' \
    'if test -f "$SEQUENTIAL_PGREP_COUNT"; then count="$(cat "$SEQUENTIAL_PGREP_COUNT")"; fi' \
    'count=$((count + 1))' \
    'printf "%s\n" "$count" >"$SEQUENTIAL_PGREP_COUNT"' \
    'test "$count" -ge 2' \
    >"$SEQUENTIAL_FAKE_BIN/pgrep"
chmod 755 "$SEQUENTIAL_FAKE_BIN/pgrep"

if SEQUENTIAL_PGREP_COUNT="$SEQUENTIAL_PGREP_COUNT" \
    PATH="$SEQUENTIAL_FAKE_BIN:$PATH" \
    "$INSTALLER" \
    --source "$SOURCE_APP" \
    --destination "$DESTINATION" \
    --no-launch \
    --skip-chrome
then
    fail "installer ignored StayPane starting after its first process check"
fi

AFTER_LATE_LAUNCH_HASH="$(
    shasum -a 256 "$DESTINATION/Contents/MacOS/StayPane"
)"
[[ "$FIRST_INSTALL_HASH" == "$AFTER_LATE_LAUNCH_HASH" ]] \
    || fail "late running-process refusal changed the installed app"

LOCK_FILE="$TEST_ROOT/Applications/.staypane-install.lock"
shlock -p "$$" -f "$LOCK_FILE" \
    || fail "test could not acquire the installer lock"
if "$INSTALLER" \
    --source "$SOURCE_APP" \
    --destination "$DESTINATION" \
    --no-launch \
    --skip-chrome
then
    fail "installer ignored a concurrent installation lock"
fi
rm "$LOCK_FILE"

[[ "$RECOVERY_HASH" == "$(
    shasum -a 256 "$USER_DATA_DIRECTORY/active-session.json"
)" ]] || fail "installation changed Session Recovery data"
[[ "$HISTORY_HASH" == "$(
    shasum -a 256 "$USER_DATA_DIRECTORY/session-history.json"
)" ]] || fail "installation changed Session History"
[[ "$PREFERENCES_HASH" == "$(
    shasum -a 256 "$PREFERENCES_DIRECTORY/org.staypane.app.plist"
)" ]] || fail "installation changed StayPane preferences"

echo "Local install test passed."
