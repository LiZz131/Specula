#!/usr/bin/env bash
set -euo pipefail

HARNESS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
OUTPUT_ROOT="$(CDPATH= cd -- "$HARNESS_DIR/.." && pwd)"
WORK_TREE="${SPECULA_WORK_SOURCE:-/work/work-source}"
TRACE_NAME="${1:-startup-mutation-restart-fresh}"
TRACE_FILE="$OUTPUT_ROOT/traces/$TRACE_NAME.ndjson"
RAW_FILE="$OUTPUT_ROOT/traces/original/$TRACE_NAME.ndjson.original"
RUN_LOG="$OUTPUT_ROOT/spec/output/repair/harness-$TRACE_NAME.log"
NORMALIZER="$HARNESS_DIR/normalize-trace.jq"

case "$TRACE_NAME" in
    *[!A-Za-z0-9._-]*|'')
        echo "trace name may contain only letters, digits, dot, underscore, and hyphen" >&2
        exit 64
        ;;
esac

mkdir -p "$OUTPUT_ROOT/traces/original" "$OUTPUT_ROOT/spec/output/repair"
"$HARNESS_DIR/apply.sh"

rm -f -- "$TRACE_FILE" "$RAW_FILE"
set +e
timeout --signal=TERM --kill-after=20s 300s \
    ant -f "$WORK_TREE/build.xml" \
        -Dtestcase=SpeculaTraceHarnessTest \
        -Dspecula.trace.file="$RAW_FILE" \
        test-core-java >"$RUN_LOG" 2>&1
TEST_EXIT=$?
set -e
printf '%s\n' "command: timeout --signal=TERM --kill-after=20s 300s ant -f /work/work-source/build.xml -Dtestcase=SpeculaTraceHarnessTest -Dspecula.trace.file=$RAW_FILE test-core-java" >>"$RUN_LOG"
printf 'exit_code: %s\n' "$TEST_EXIT" >>"$RUN_LOG"
if [ "$TEST_EXIT" -ne 0 ]; then
    exit "$TEST_EXIT"
fi
if [ ! -s "$RAW_FILE" ]; then
    echo "harness passed without producing a nonempty trace" | tee -a "$RUN_LOG" >&2
    exit 67
fi

jq -c -f "$NORMALIZER" "$RAW_FILE" >"$TRACE_FILE"
jq -e '(.tag == "trace") and (.event.name | type == "string") and
       (.event.nid | type == "string") and (.event.peer | type == "string") and
       (.event.state.zxid | type == "number") and
       (.event.state.modelZxid | type == "number") and
       (.event.state.epoch | type == "number") and
       (.event.state.acceptedEpoch | type == "number") and
       (.event.state.role | type == "string") and
       (.event.state.mode | type == "string")' "$TRACE_FILE" >/dev/null

{
    printf 'trace_lines: '
    wc -l <"$TRACE_FILE"
    sha256sum "$RAW_FILE" "$TRACE_FILE"
    jq -r '.event.name' "$TRACE_FILE" | sort | uniq -c
} >>"$RUN_LOG"

echo "$TRACE_FILE"
