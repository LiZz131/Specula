#!/usr/bin/env bash
set -euo pipefail

HARNESS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
OUTPUT_ROOT="$(CDPATH= cd -- "$HARNESS_DIR/.." && pwd)"
SPEC_DIR="$OUTPUT_ROOT/spec"
LIB_DIR="${SPECULA_LIB_DIR:-/work/lib}"
OUT_DIR="${SPECULA_VALIDATION_OUT:-$SPEC_DIR/output/validation-backedge}"
SUMMARY="$OUT_DIR/trace-suite.tsv"
OUT_REL="${OUT_DIR#"$OUTPUT_ROOT/"}"

mkdir -p "$OUT_DIR"
ACTIVE_META=""
cleanup_meta() {
    if [ -n "$ACTIVE_META" ] && [ -d "$ACTIVE_META" ]; then
        rm -rf -- "$ACTIVE_META"
    fi
}
trap cleanup_meta EXIT INT TERM
printf 'trace\tsha256\tlines\texit_code\tstates_generated\tdistinct_states\tqueue\tlog\n' >"$SUMMARY"

TRACE_COUNT=0
FAILURES=0
for TRACE_FILE in "$OUTPUT_ROOT"/traces/*.ndjson; do
    [ -f "$TRACE_FILE" ] || continue
    TRACE_COUNT=$((TRACE_COUNT + 1))
    TRACE_BASE="$(basename "$TRACE_FILE" .ndjson)"
    LOG_FILE="$OUT_DIR/trace-$TRACE_BASE.log"
    META_DIR="$(mktemp -d "$OUT_DIR/.tlc-state-trace-$TRACE_BASE.XXXXXX")"
    ACTIVE_META="$META_DIR"
    set +e
    (
        cd "$SPEC_DIR"
        JSON="$TRACE_FILE" timeout --signal=TERM --kill-after=20s 300s \
            java -Djava.io.tmpdir="$META_DIR" -XX:+UseParallelGC -Xmx8G \
            -cp "$LIB_DIR/tla2tools.jar:$LIB_DIR/CommunityModules-deps.jar" \
            tlc2.TLC -workers 4 -config Trace.cfg -metadir "$META_DIR" \
            -deadlock Trace.tla
    ) >"$LOG_FILE" 2>&1
    TLC_EXIT=$?
    set -e
    printf '%s\n' "command: JSON=$TRACE_FILE timeout --signal=TERM --kill-after=20s 300s java -Djava.io.tmpdir=$META_DIR -XX:+UseParallelGC -Xmx8G -cp $LIB_DIR/tla2tools.jar:$LIB_DIR/CommunityModules-deps.jar tlc2.TLC -workers 4 -config Trace.cfg -metadir $META_DIR -deadlock Trace.tla" >>"$LOG_FILE"
    printf 'exit_code: %s\n' "$TLC_EXIT" >>"$LOG_FILE"
    rm -rf -- "$META_DIR"
    ACTIVE_META=""

    FINAL_STATS="$(sed -n 's/^\([0-9][0-9]*\) states generated, \([0-9][0-9]*\) distinct states found, \([0-9][0-9]*\) states left on queue\.$/\1\t\2\t\3/p' "$LOG_FILE" | tail -1)"
    if [ -z "$FINAL_STATS" ]; then
        FINAL_STATS="0\t0\t-1"
    fi
    printf '%s\t%s\t%s\t%s\t%b\t%s\n' \
        "$TRACE_BASE" "$(sha256sum "$TRACE_FILE" | cut -d' ' -f1)" \
        "$(wc -l <"$TRACE_FILE")" "$TLC_EXIT" "$FINAL_STATS" \
        "$OUT_REL/$(basename "$LOG_FILE")" >>"$SUMMARY"
    if [ "$TLC_EXIT" -ne 0 ] ||
       ! rg -q 'Model checking completed\. No error has been found\.' "$LOG_FILE" ||
       ! rg -q ', 0 states left on queue\.' "$LOG_FILE"; then
        FAILURES=$((FAILURES + 1))
    fi
done

if [ "$TRACE_COUNT" -eq 0 ]; then
    echo "no retained trace files found" >&2
    exit 66
fi
if [ "$FAILURES" -ne 0 ]; then
    echo "$FAILURES of $TRACE_COUNT traces failed validation" >&2
    exit 1
fi
echo "validated all $TRACE_COUNT retained traces"
