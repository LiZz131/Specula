#!/usr/bin/env bash
set -euo pipefail

HARNESS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
OUTPUT_ROOT="$(CDPATH= cd -- "$HARNESS_DIR/.." && pwd)"
WORK_TREE="${SPECULA_WORK_SOURCE:-/work/work-source}"
OUT_DIR="${SPECULA_VALIDATION_OUT:-$OUTPUT_ROOT/spec/output/validation-backedge}"
PATCH_FILE="$HARNESS_DIR/patches/instrumentation.patch"
LOG_FILE="$OUT_DIR/instrumentation-provenance.log"

if [ "$WORK_TREE" != "/work/work-source" ]; then
    echo "refusing provenance check outside /work/work-source" >&2
    exit 64
fi
mkdir -p "$OUT_DIR"

set +e
timeout --signal=TERM --kill-after=5s 30s \
    patch -d "$WORK_TREE" -p1 -R --dry-run <"$PATCH_FILE" >"$LOG_FILE" 2>&1
PATCH_EXIT=$?
set -e
printf '%s\n' "command: timeout --signal=TERM --kill-after=5s 30s patch -d /work/work-source -p1 -R --dry-run < $PATCH_FILE" >>"$LOG_FILE"
printf 'exit_code: %s\n' "$PATCH_EXIT" >>"$LOG_FILE"
if [ "$PATCH_EXIT" -ne 0 ]; then
    exit "$PATCH_EXIT"
fi

set +e
cmp -s "$HARNESS_DIR/src/SpeculaTrace.java" \
    "$WORK_TREE/src/java/main/org/apache/zookeeper/server/SpeculaTrace.java"
TRACE_MODULE_EXIT=$?
cmp -s "$HARNESS_DIR/src/SpeculaTraceHarnessTest.java" \
    "$WORK_TREE/src/java/test/org/apache/zookeeper/server/quorum/SpeculaTraceHarnessTest.java"
TEST_SOURCE_EXIT=$?
set -e
printf '%s\n' "command: cmp -s harness/src/SpeculaTrace.java /work/work-source/src/java/main/org/apache/zookeeper/server/SpeculaTrace.java" >>"$LOG_FILE"
printf 'exit_code: %s\n' "$TRACE_MODULE_EXIT" >>"$LOG_FILE"
printf '%s\n' "command: cmp -s harness/src/SpeculaTraceHarnessTest.java /work/work-source/src/java/test/org/apache/zookeeper/server/quorum/SpeculaTraceHarnessTest.java" >>"$LOG_FILE"
printf 'exit_code: %s\n' "$TEST_SOURCE_EXIT" >>"$LOG_FILE"
sha256sum "$PATCH_FILE" "$HARNESS_DIR/src/SpeculaTrace.java" \
    "$HARNESS_DIR/src/SpeculaTraceHarnessTest.java" >>"$LOG_FILE"

if [ "$TRACE_MODULE_EXIT" -ne 0 ] || [ "$TEST_SOURCE_EXIT" -ne 0 ]; then
    exit 1
fi
