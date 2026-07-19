#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT="${1:?repository path is required}"
USER_HOME_DIRECTORY="${2:?home path is required}"

escape_basic_regular_expression() {
    sed 's/[][\\.^$*|]/\\&/g'
}

REPOSITORY_PATTERN="$(
    printf '%s' "$REPOSITORY_ROOT" | escape_basic_regular_expression
)"
HOME_PATTERN="$(
    printf '%s' "$USER_HOME_DIRECTORY" | escape_basic_regular_expression
)"

sed \
    -e "s|$REPOSITORY_PATTERN|<repository>|g" \
    -e "s|$HOME_PATTERN|<home>|g" \
    | sed -E 's#https?://[^[:space:]"]+#<redacted-url>#g'
