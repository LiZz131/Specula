#!/usr/bin/env bash
set -euo pipefail

HARNESS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
OUTPUT_ROOT="$(CDPATH= cd -- "$HARNESS_DIR/.." && pwd)"
SPEC_DIR="$OUTPUT_ROOT/spec"
LIB_DIR="${SPECULA_LIB_DIR:-/work/lib}"
OUT_DIR="${SPECULA_VALIDATION_OUT:-$SPEC_DIR/output/validation-backedge}"

export SPECULA_VALIDATION_OUT="$OUT_DIR"
mkdir -p "$OUT_DIR"
ACTIVE_META=""
cleanup_meta() {
    if [ -n "$ACTIVE_META" ] && [ -d "$ACTIVE_META" ]; then
        rm -rf -- "$ACTIVE_META"
    fi
}
trap cleanup_meta EXIT INT TERM

"$HARNESS_DIR/verify-provenance.sh"

SANY_LOG="$OUT_DIR/sany.log"
set +e
(
    cd "$SPEC_DIR"
    timeout --signal=TERM --kill-after=10s 120s \
        java -cp "$LIB_DIR/tla2tools.jar:$LIB_DIR/CommunityModules-deps.jar" \
        tla2sany.SANY base.tla MC.tla Trace.tla
) >"$SANY_LOG" 2>&1
SANY_EXIT=$?
set -e
printf '%s\n' "command: timeout --signal=TERM --kill-after=10s 120s java -cp $LIB_DIR/tla2tools.jar:$LIB_DIR/CommunityModules-deps.jar tla2sany.SANY base.tla MC.tla Trace.tla" >>"$SANY_LOG"
printf 'exit_code: %s\n' "$SANY_EXIT" >>"$SANY_LOG"
if [ "$SANY_EXIT" -ne 0 ]; then
    exit "$SANY_EXIT"
fi

"$HARNESS_DIR/validate-suite.sh"

run_tlc() {
    local module="$1"
    local config="$2"
    local log="$3"
    local meta
    meta="$(mktemp -d "$OUT_DIR/.tlc-state-${module%.tla}.XXXXXX")"
    ACTIVE_META="$meta"
    set +e
    (
        cd "$SPEC_DIR"
        timeout --signal=TERM --kill-after=20s 300s \
            java -Djava.io.tmpdir="$meta" -XX:+UseParallelGC -Xmx8G \
            -cp "$LIB_DIR/tla2tools.jar:$LIB_DIR/CommunityModules-deps.jar" \
            tlc2.TLC -workers 4 -config "$config" -metadir "$meta" "$module"
    ) >"$log" 2>&1
    local status=$?
    set -e
    printf '%s\n' "command: timeout --signal=TERM --kill-after=20s 300s java -Djava.io.tmpdir=$meta -XX:+UseParallelGC -Xmx8G -cp $LIB_DIR/tla2tools.jar:$LIB_DIR/CommunityModules-deps.jar tlc2.TLC -workers 4 -config $config -metadir $meta $module" >>"$log"
    printf 'exit_code: %s\n' "$status" >>"$log"
    rm -rf -- "$meta"
    ACTIVE_META=""
    if [ "$status" -ne 0 ]; then
        return "$status"
    fi
    rg -q 'Model checking completed\. No error has been found\.' "$log"
    rg -q 'states left on queue\.' "$log"
    rg -q ', 0 states left on queue\.' "$log"
}

mkdir -p "$OUT_DIR"
run_tlc base.tla base.cfg "$OUT_DIR/base-canonical-bfs.log"
run_tlc MC.tla MC.cfg "$OUT_DIR/mc-canonical-bfs.log"
"$HARNESS_DIR/generate-suite-manifest.sh" "$OUT_DIR"
