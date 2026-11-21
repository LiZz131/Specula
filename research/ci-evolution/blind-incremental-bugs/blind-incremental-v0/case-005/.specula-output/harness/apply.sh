#!/usr/bin/env bash
set -euo pipefail

HARNESS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
WORK_TREE="${SPECULA_WORK_SOURCE:-/work/work-source}"
PATCH_FILE="$HARNESS_DIR/patches/instrumentation.patch"

if [ "$WORK_TREE" != "/work/work-source" ]; then
    echo "refusing to instrument a tree other than /work/work-source: $WORK_TREE" >&2
    exit 64
fi
if [ ! -d "$WORK_TREE/.git" ] || [ ! -s "$PATCH_FILE" ]; then
    echo "missing writable exact-old worktree or instrumentation patch" >&2
    exit 66
fi

if git -C "$WORK_TREE" apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
    echo "tracked instrumentation patch is already applied"
elif git -C "$WORK_TREE" apply --check "$PATCH_FILE"; then
    git -C "$WORK_TREE" apply "$PATCH_FILE"
    echo "applied tracked instrumentation patch"
else
    echo "worktree is neither pristine nor an exact application of the recorded patch" >&2
    exit 65
fi

install -m 0644 "$HARNESS_DIR/src/SpeculaTrace.java" \
    "$WORK_TREE/src/java/main/org/apache/zookeeper/server/SpeculaTrace.java"
install -m 0644 "$HARNESS_DIR/src/SpeculaTraceHarnessTest.java" \
    "$WORK_TREE/src/java/test/org/apache/zookeeper/server/quorum/SpeculaTraceHarnessTest.java"

sha256sum "$PATCH_FILE" "$HARNESS_DIR/src/SpeculaTrace.java" \
    "$HARNESS_DIR/src/SpeculaTraceHarnessTest.java"

