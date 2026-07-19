#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

fail() {
    echo "Release contract failed: $1" >&2
    exit 1
}

LICENSE_PATH="$REPOSITORY_ROOT/LICENSE"
README_PATH="$REPOSITORY_ROOT/README.md"
INSTALL_PATH="$REPOSITORY_ROOT/docs/INSTALL.md"
ROADMAP_PATH="$REPOSITORY_ROOT/ROADMAP.md"
RELEASE_MATRIX_PATH="$REPOSITORY_ROOT/docs/manual-testing/v1-release-matrix.md"
AUDIT_PATH="$REPOSITORY_ROOT/scripts/audit-source-release.sh"
VERIFY_PATH="$REPOSITORY_ROOT/scripts/verify-source-release.sh"
REDACTOR_PATH="$REPOSITORY_ROOT/scripts/redact-release-log.sh"
WORKFLOW_PATH="$REPOSITORY_ROOT/.github/workflows/verify.yml"
NODE_VERSION_PATH="$REPOSITORY_ROOT/.node-version"

test -f "$LICENSE_PATH" || fail "LICENSE is missing"
grep -Fq "MIT License" "$LICENSE_PATH" \
    || fail "LICENSE is not the MIT License"
grep -Fq "Permission is hereby granted, free of charge" "$LICENSE_PATH" \
    || fail "LICENSE is missing the MIT permission grant"
grep -Fiq "commercial and closed-source reuse" "$README_PATH" \
    || fail "README does not explain commercial and closed-source reuse"
grep -Fq "license notice" "$README_PATH" \
    || fail "README does not explain the preserved license notice"

test -f "$INSTALL_PATH" || fail "docs/INSTALL.md is missing"
test -f "$NODE_VERSION_PATH" || fail ".node-version is missing"
grep -Eq '^22([.]|$)' "$NODE_VERSION_PATH" \
    || fail ".node-version does not select the documented Node.js line"
for required_text in \
    "Apple silicon" \
    "macOS 26" \
    "Xcode 26" \
    "Node.js" \
    "git clone" \
    "make verify" \
    "make setup-chrome" \
    "make run" \
    "Developer mode" \
    "Load unpacked" \
    "Verify the Bridge Connection" \
    "Remove Chrome Integration" \
    "Update StayPane" \
    "unsigned" \
    "Accessibility" \
    "honest self-control" \
    "local-only" \
    "Unsupported Environments"
do
    grep -Fiq "$required_text" "$INSTALL_PATH" \
        || fail "installation guide is missing: $required_text"
done
grep -Fiq "no paid Apple or Google developer account" "$INSTALL_PATH" \
    || fail "installation guide does not explain the no-paid-account setup"

test -f "$ROADMAP_PATH" || fail "ROADMAP.md is missing"
grep -Fiq "Safari first" "$ROADMAP_PATH" \
    || fail "roadmap does not place Safari first"
grep -Fiq "other Chromium browsers next" "$ROADMAP_PATH" \
    || fail "roadmap does not place other Chromium browsers second"
grep -Fiq "Firefox afterward" "$ROADMAP_PATH" \
    || fail "roadmap does not place Firefox third"
grep -Fiq "not a promise" "$ROADMAP_PATH" \
    || fail "roadmap overstates future integrations"

test -f "$RELEASE_MATRIX_PATH" \
    || fail "the consolidated v1 manual acceptance matrix is missing"
for matrix_case in \
    "Normal Completion" \
    "Early Reset" \
    "Closed Targets" \
    "Transient Child Interface" \
    "Multiple Displays" \
    "Spaces" \
    "Full Screen" \
    "Sleep" \
    "Application Crash" \
    "Mac Restart" \
    "Accessibility Permission Loss" \
    "Native Bridge Loss" \
    "Multiple Tab Targets" \
    "Navigation Scopes" \
    "Multiple Chrome Profiles" \
    "Incognito" \
    "Restoration Failure" \
    "Short Real Session"
do
    grep -Fiq "$matrix_case" "$RELEASE_MATRIX_PATH" \
        || fail "manual matrix is missing: $matrix_case"
done

for context_path in \
    "docs/contexts/product/CONTEXT.md" \
    "docs/contexts/macos/CONTEXT.md" \
    "docs/contexts/chrome/CONTEXT.md" \
    "docs/contexts/native-bridge/CONTEXT.md"
do
    test -f "$REPOSITORY_ROOT/$context_path" \
        || fail "domain context is missing: $context_path"
    grep -Fq "$context_path" "$REPOSITORY_ROOT/CONTEXT-MAP.md" \
        || fail "CONTEXT-MAP does not link: $context_path"
done

test -f "$AUDIT_PATH" || fail "source-release audit is missing"
test -f "$VERIFY_PATH" || fail "source-release verifier is missing"
test -f "$REDACTOR_PATH" || fail "release-log redactor is missing"
test -f "$WORKFLOW_PATH" || fail "GitHub verification workflow is missing"
grep -Eq '^verify:' "$REPOSITORY_ROOT/Makefile" \
    || fail "Makefile has no public verify target"
grep -Fq "make verify" "$WORKFLOW_PATH" \
    || fail "GitHub workflow does not use the public verify target"
grep -Fq "node-version: 22" "$WORKFLOW_PATH" \
    || fail "GitHub workflow does not use the documented Node.js line"
grep -Eq 'runs-on: macos-' "$WORKFLOW_PATH" \
    || fail "GitHub verification does not run on macOS"

bash "$AUDIT_PATH" --source-only "$REPOSITORY_ROOT" \
    || fail "source-release audit rejected the repository"

PRIVATE_SAMPLE_ROOT="/Users/example/Private StayPane"
PRIVATE_SAMPLE_HOME="/Users/example"
REDACTED_SAMPLE="$(
    printf '%s\n' \
        "$PRIVATE_SAMPLE_ROOT/Tests failed at https://private.example/path" \
        "$PRIVATE_SAMPLE_HOME/Library/private.json" \
        | bash "$REDACTOR_PATH" \
            "$PRIVATE_SAMPLE_ROOT" \
            "$PRIVATE_SAMPLE_HOME"
)"
grep -Fq '<repository>' <<<"$REDACTED_SAMPLE" \
    || fail "release logs do not redact the repository path"
grep -Fq '<home>' <<<"$REDACTED_SAMPLE" \
    || fail "release logs do not redact the home path"
grep -Fq '<redacted-url>' <<<"$REDACTED_SAMPLE" \
    || fail "release logs do not redact URLs"
if grep -Fq 'private.example' <<<"$REDACTED_SAMPLE"; then
    fail "release logs retain a private URL"
fi

echo "Release documentation contract passed."
