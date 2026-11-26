#!/usr/bin/env bash
# Real TLC trace validation of traces/<scenario>.ndjson:
#  (1) Trace.cfg: existential completion property TraceMatched + invariants
#  (2) Trace-witness.cfg: full-consumption witness (TraceIncomplete violated)
set -u
sc="$1"; here="$(cd "$(dirname "$0")" && pwd)"
export JSON="$here/../traces/$sc.ndjson"
TLC_HEAP=8g "$here/tlc.sh" "trace-$sc" Trace.tla Trace.cfg 1800s -workers 1
TLC_HEAP=8g "$here/tlc.sh" "trace-witness-$sc" Trace.tla Trace-witness.cfg 1800s -workers 1
a="$here/output/trace-$sc.log"; b="$here/output/trace-witness-$sc.log"
n=$(wc -l < "$JSON")
okA=0; grep -q "Model checking completed. No error has been found" "$a" && okA=1
okB=0; grep -q "Invariant TraceIncomplete is violated" "$b" && okB=1
lastl=$(grep -E '^/\\ l = ' "$b" | tail -1 | awk '{print $4}')
echo "$sc events=$n completion=$okA witness=$okB witness_final_l=$lastl"
