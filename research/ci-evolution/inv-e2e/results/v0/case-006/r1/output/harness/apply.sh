#!/usr/bin/env bash
# Materialize a clean copy of the updated source revision from the artifact
# repository (the artifact itself is never modified) and apply the rebased
# instrumentation patch to it.
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
SOURCE_REPO="${SOURCE_REPO:-$OUTPUT_ROOT/artifact}"
EXPECTED_REV="${EXPECTED_REV:-c780d355cfeae6ee6be52c50c1f0bd7d30c6657a}"   # neutral commit "update"
REV="${REV:-$EXPECTED_REV}"
TARGET_TREE="${TARGET_TREE:-$OUTPUT_ROOT/build/worktrees/instr-$REV}"
PATCH_FILE="$HARNESS_DIR/patches/instrumentation.patch"

test "$(git -C "$SOURCE_REPO" rev-parse "$REV^{commit}")" = "$REV"
rm -rf "$TARGET_TREE"; mkdir -p "$TARGET_TREE"
git -C "$SOURCE_REPO" archive "$REV" | tar -x -C "$TARGET_TREE"
(cd "$TARGET_TREE" && git apply --check "$PATCH_FILE" && git apply "$PATCH_FILE")
echo "instrumentation applied to $TARGET_TREE (rev $REV)"
