#!/usr/bin/env bash
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
SPEC_DIR="$OUTPUT_ROOT/spec"
TRACE_FILE="$OUTPUT_ROOT/traces/quorum_read.ndjson"
QUORUM_TRACE_FILE="$OUTPUT_ROOT/traces/quorum_loss.ndjson"
TLA_CP="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
STATE_ROOT="/dev/shm/specula-v0-case-006"

cleanup() {
    if [ -d "$STATE_ROOT/harness-trace" ]; then
        find "$STATE_ROOT/harness-trace" -depth -delete
    fi
    if [ -d "$STATE_ROOT/harness-mc" ]; then
        find "$STATE_ROOT/harness-mc" -depth -delete
    fi
    rmdir "$STATE_ROOT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

test -s "$TRACE_FILE"
test -s "$QUORUM_TRACE_FILE"
cd "$SPEC_DIR"

java -cp "$TLA_CP" tla2sany.SANY base.tla > output/sany-base.log 2>&1
java -cp "$TLA_CP" tla2sany.SANY Trace.tla > output/sany-trace.log 2>&1
java -cp "$TLA_CP" tla2sany.SANY MC.tla > output/sany-mc.log 2>&1

mkdir -p "$STATE_ROOT/harness-trace"
timeout 5m java -XX:+UseParallelGC -cp "$TLA_CP" tlc2.TLC \
    -workers 1 -coverage 1 -metadir "$STATE_ROOT/harness-trace" \
    -config Trace.cfg Trace.tla > output/trace-quorum-read.log 2>&1
find "$STATE_ROOT/harness-trace" -depth -delete

mkdir -p "$STATE_ROOT/harness-trace"
timeout 5m java -XX:+UseParallelGC -cp "$TLA_CP" tlc2.TLC \
    -workers 1 -coverage 1 -metadir "$STATE_ROOT/harness-trace" \
    -config Trace_quorum_loss.cfg Trace.tla > output/trace-quorum-loss.log 2>&1
find "$STATE_ROOT/harness-trace" -depth -delete

mkdir -p "$STATE_ROOT/harness-mc"
timeout 3m java -XX:+UseParallelGC -cp "$TLA_CP" tlc2.TLC \
    -workers 4 -coverage 1 -metadir "$STATE_ROOT/harness-mc" \
    -config MC_complete_core.cfg MC.tla > output/mc-complete-core.log 2>&1
find "$STATE_ROOT/harness-mc" -depth -delete

echo "trace validation and complete-core model check succeeded"
