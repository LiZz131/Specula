#!/usr/bin/env bash
# Rebased (V1): export a revision of the writable artifact repository into a
# fresh build tree and apply the instrumentation patch there. The artifact
# working tree itself is never modified.
#   TARGET_REV  : commit to export (default: the `update` commit, HEAD)
#   TARGET_TREE : output tree (default: ../build/tree-<rev12>)
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
ARTIFACT="${ARTIFACT:-$OUTPUT_ROOT/artifact}"
UPDATE_COMMIT="c780d355cfeae6ee6be52c50c1f0bd7d30c6657a"
BASELINE_COMMIT="7289d1c5e049933b90a9692bbf508714bee02fce"
TARGET_REV="${TARGET_REV:-$UPDATE_COMMIT}"
REV_SHA="$(git -C "$ARTIFACT" rev-parse "$TARGET_REV^{commit}")"
case "$REV_SHA" in
  "$UPDATE_COMMIT"|"$BASELINE_COMMIT") ;;
  *) echo "unexpected revision $REV_SHA" >&2; exit 1 ;;
esac
TARGET_TREE="${TARGET_TREE:-$OUTPUT_ROOT/build/tree-${REV_SHA:0:12}}"
PATCH_FILE="$HARNESS_DIR/patches/instrumentation.patch"

rm -rf "$TARGET_TREE"
mkdir -p "$TARGET_TREE"
git -C "$ARTIFACT" archive "$REV_SHA" | tar -x -C "$TARGET_TREE"
( cd "$TARGET_TREE" && git apply --check "$PATCH_FILE" && git apply "$PATCH_FILE" )
# Standalone reproduction test (no instrumentation dependency).
cp "$HARNESS_DIR/repro/specula_repro_readindex_test.go" "$TARGET_TREE/"
echo "rev=$REV_SHA tree=$TARGET_TREE instrumentation+repro applied"
