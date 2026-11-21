#!/usr/bin/env bash
# Idempotently apply the rebased instrumentation (v2) to the writable copy of
# the updated source. v0 (patches/instrumentation-v0.patch) is retained for
# provenance; v2 = v0 hunks unchanged + update-local probes/fields/scenarios.
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
TARGET_TREE="${TARGET_TREE:-$OUTPUT_ROOT/build/work-source}"
UPDATE_COMMIT="c780d355cfeae6ee6be52c50c1f0bd7d30c6657a"
PATCH_FILE="$HARNESS_DIR/patches/instrumentation.patch"

test -d "$TARGET_TREE/.git"
test "$(git -C "$TARGET_TREE" rev-parse HEAD)" = "$UPDATE_COMMIT"
if git -C "$TARGET_TREE" apply --check "$PATCH_FILE" 2>/dev/null; then
    git -C "$TARGET_TREE" apply "$PATCH_FILE"
    echo "instrumentation applied to $TARGET_TREE"
elif git -C "$TARGET_TREE" apply --reverse --check "$PATCH_FILE" 2>/dev/null; then
    echo "instrumentation already applied to $TARGET_TREE"
else
    echo "instrumentation patch neither applies nor is already applied" >&2
    exit 1
fi
