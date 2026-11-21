#!/usr/bin/env bash
# Trace-first validation: SANY all modules, then real TLC replay of every
# retained fresh trace (TraceMatched temporal property + post-state checks +
# safety/update invariants).  delayed_ack is replayed twice: conformance
# (must pass) and a freshness witness (UpdReadAckAfterEnqueue expected to be
# violated by the real execution).
set -uo pipefail
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
SPEC_DIR="$OUTPUT_ROOT/spec"
TLA_CP="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
STATE_ROOT="/dev/shm/specula-e2e-case-006"
cleanup() { [ -d "$STATE_ROOT/trace" ] && find "$STATE_ROOT/trace" -depth -delete; rmdir "$STATE_ROOT" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
cd "$SPEC_DIR"; mkdir -p output
status=0
for m in base MC UpdateProps Update Trace; do
    timeout 5m java -cp "$TLA_CP" tla2sany.SANY "$m.tla" > "output/sany-$m.log" 2>&1 || { echo "SANY $m FAILED"; status=1; }
done
run_trace() {  # cfg log expect(pass|violation)
    local cfg=$1 log=$2 expect=$3
    test -s "$(sed -n 's/.*TraceFile = "\(.*\)"/\1/p' "$cfg")" || { echo "missing trace for $cfg"; status=1; return; }
    mkdir -p "$STATE_ROOT/trace"
    timeout 10m java -XX:+UseParallelGC -cp "$TLA_CP" tlc2.TLC -workers 1 -coverage 1 \
        -metadir "$STATE_ROOT/trace" -config "$cfg" Trace.tla > "output/$log" 2>&1
    local rc=$?
    find "$STATE_ROOT/trace" -depth -delete
    if [ "$expect" = pass ]; then
        if [ $rc -eq 0 ] && grep -q "Model checking completed. No error has been found" "output/$log"; then
            echo "PASS $cfg ($(grep -o '[0-9]* distinct states found' "output/$log" | head -1))"
        else echo "FAIL $cfg rc=$rc (see output/$log)"; status=1; fi
    else
        local inv=UpdReadAckAfterEnqueue
        [ "$expect" = violation-linearizable ] && inv=UpdReadIndexLinearizable
        if grep -q "Invariant $inv is violated" "output/$log"; then
            echo "EXPECTED-WITNESS $cfg: $inv violated by the real execution"
        else echo "WITNESS-MISSING $cfg rc=$rc (see output/$log)"; status=1; fi
    fi
}
run_trace Trace.cfg trace-quorum-read.log pass
run_trace Trace_quorum_loss.cfg trace-quorum-loss.log pass
run_trace Trace_read_reuse.cfg trace-read-reuse.log pass
run_trace Trace_forwarded_read.cfg trace-forwarded-read.log pass
run_trace Trace_delayed_ack.cfg trace-delayed-ack.log pass
run_trace Trace_step_down_reads.cfg trace-step-down-reads.log pass
run_trace Trace_higher_term_reads.cfg trace-higher-term-reads.log pass
run_trace Trace_stale_read_reuse.cfg trace-stale-read-reuse.log pass
run_trace Trace_delayed_ack_freshness.cfg trace-delayed-ack-freshness.log violation
run_trace Trace_stale_read_reuse_witness.cfg trace-stale-read-reuse-witness.log violation-linearizable
exit $status
