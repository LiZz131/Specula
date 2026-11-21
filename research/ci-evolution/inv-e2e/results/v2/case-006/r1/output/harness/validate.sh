#!/usr/bin/env bash
# Trace-first validation of every fresh new-version trace (real TLC replay,
# TraceMatched temporal completion + post-state checks), then the stale-ack
# evidence evaluation. States live under /dev/shm and are removed per run.
set -uo pipefail
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
SPEC_DIR="$OUTPUT_ROOT/spec"
TRACES="$OUTPUT_ROOT/traces"
TLA_CP="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
STATE_ROOT="/dev/shm/specula-e2e-case-006"
SUMMARY="$SPEC_DIR/output/trace-validation-summary.log"
cd "$SPEC_DIR"
mkdir -p output "$STATE_ROOT"
: > "$SUMMARY"
for m in base MC Trace TraceUpd Update; do
    java -cp "$TLA_CP" tla2sany.SANY "$m.tla" > "output/sany-$m.log" 2>&1
    if grep -qiE "^\*\*\* Errors|Semantic errors|Parse Error" "output/sany-$m.log"; then
        echo "SANY $m FAILED" | tee -a "$SUMMARY"; exit 1
    fi
    echo "SANY $m ok" >> "$SUMMARY"
done
status=0
run() { # trace cfg log
    local trace="$1" cfg="$2" log="$3"
    local dir="$STATE_ROOT/trace-$(basename "$log" .log)"
    mkdir -p "$dir"
    JSON="$TRACES/$trace.ndjson" timeout 10m java -XX:+UseParallelGC -cp "$TLA_CP" tlc2.TLC \
        -workers 1 -coverage 1 -metadir "$dir" -teSpecOutDir output/te -config "$cfg" TraceUpd.tla > "output/$log" 2>&1
    local rc=$?
    find "$dir" -depth -delete 2>/dev/null
    local recs; recs=$(wc -l < "$TRACES/$trace.ndjson")
    local res; res=$(grep -E "^Model checking completed|^Error:|violated|Temporal properties" "output/$log" | head -2 | tr '\n' ' ')
    local depth; depth=$(grep -E "depth of the complete state graph" "output/$log" | grep -oE "[0-9]+" | head -1)
    echo "$trace cfg=$cfg records=$recs rc=$rc depth=${depth:-?} :: $res" | tee -a "$SUMMARY"
    return $rc
}
for t in quorum_read quorum_loss read_reuse forwarded_read stepdown_pending; do
    run "$t" Trace.cfg "trace-$t.log" || status=1
done
run stale_ack_reuse Trace_stale_ack.cfg trace-stale_ack_reuse.log || status=1
# Evidence runs: a violation of the final-state oracle is EXPECTED here.
run stale_ack_reuse Trace_stale_ack_evidence_fresh.cfg trace-stale_ack_reuse-evidence-fresh.log
run stale_ack_reuse Trace_stale_ack_evidence_lin.cfg trace-stale_ack_reuse-evidence-lin.log
echo "(stale_ack_reuse evidence runs: final-state violation of TrFinal* expected)" >> "$SUMMARY"
# Negative controls: mutated copies must be rejected (TraceCanProgress violation).
python3 -I "$HARNESS_DIR/mutate.py" "$TRACES" >> "$SUMMARY"
for f in "$TRACES"/mutants/*.ndjson; do
    m=$(basename "$f" .ndjson)
    TRACES_SAVE="$TRACES"; TRACES="$TRACES/mutants"
    run "$m" Trace.cfg "mutant-$m.log" && { echo "MUTANT $m ACCEPTED (control failed)" | tee -a "$SUMMARY"; status=1; }
    TRACES="$TRACES_SAVE"
done
rmdir "$STATE_ROOT" 2>/dev/null || true
exit $status
