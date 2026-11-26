#!/usr/bin/env bash
# Replay every retained fresh trace with real TLC against Trace.tla/Trace.cfg.
# A trace passes only when TLC completes the TraceConsumed temporal check.
set -euo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
state_parent="/dev/shm/specular-e2e-case-011"
run_state="$state_parent/trace-$$"
timeout_bound="${SPECULAR_TLC_TIMEOUT:-5m}"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
cfg="${SPECULAR_TRACE_CFG:-Trace.cfg}"
if [ "$#" -gt 0 ]; then cases=("$@"); else
    mapfile -t cases < <(cd "$suite_root/traces" && ls *.ndjson | sed 's/\.ndjson$//' | sort)
fi

cleanup() { rm -rf "$run_state"; }
trap cleanup EXIT INT TERM
mkdir -p "$run_state"
cd "$spec_dir"
summary="output/trace-validation-summary.tsv"
: > "$summary"
fail=0
for case_name in "${cases[@]}"; do
    trace="$suite_root/traces/$case_name.ndjson"
    test -s "$trace"
    log="output/trace-$case_name.log"
    set +e
    timeout "$timeout_bound" env SPECULAR_TRACE="$trace" \
        java -XX:+UseParallelGC -cp "$classpath" tlc2.TLC -workers 1 \
        -metadir "$run_state/$case_name" -config "$cfg" Trace > "$log" 2>&1
    rc=$?
    set -e
    rm -rf "$run_state/$case_name"
    records=$(wc -l < "$trace")
    if grep -q 'Model checking completed. No error has been found.' "$log" \
       && grep -q 'Checking temporal properties for the complete state space' "$log"; then
        status=PASS
    else
        status=FAIL; fail=1
    fi
    states=$(grep -oE '[0-9]+ distinct states found' "$log" | head -1 | cut -d' ' -f1)
    printf '%s\t%s\trecords=%s\tdistinct=%s\trc=%s\n' "$case_name" "$status" "$records" "${states:-?}" "$rc" | tee -a "$summary"
done
exit $fail
