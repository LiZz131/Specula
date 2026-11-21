#!/usr/bin/env bash
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_TREE="${TARGET_TREE:-/work/work-source}"
BASELINE_COMMIT="1852bbdec48ec0c188eaed7451070bbb60672192"
PATCH_FILE="$HARNESS_DIR/patches/instrumentation.patch"

test -d "$TARGET_TREE/.git"
test "$(git -C "$TARGET_TREE" rev-parse HEAD)" = "$BASELINE_COMMIT"

if git -C "$TARGET_TREE" apply --check "$PATCH_FILE" 2>/dev/null; then
    git -C "$TARGET_TREE" apply "$PATCH_FILE"
    echo "instrumentation applied to $TARGET_TREE"
elif git -C "$TARGET_TREE" apply --reverse --check "$PATCH_FILE" 2>/dev/null; then
    echo "instrumentation already applied to $TARGET_TREE"
else
    echo "instrumentation patch neither applies nor is already applied" >&2
    exit 1
fi
