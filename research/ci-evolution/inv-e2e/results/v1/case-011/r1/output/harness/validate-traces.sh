#!/usr/bin/env bash
# Real TLC trace validation of every fresh trace against Trace.tla/Trace.cfg.
# Usage: validate-traces.sh [case ...]   (default: every traces/*.ndjson)
set -uo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
state_parent="/dev/shm/specula-e2e-case-011"
run_state="$state_parent/trace-$$"
timeout_bound="${SPECULA_TLC_TIMEOUT:-5m}"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
summary="$spec_dir/output/v1-trace-summary.txt"

cleanup() { rm -rf "$run_state"; }
trap cleanup EXIT INT TERM
mkdir -p "$run_state" "$spec_dir/output"
cd "$spec_dir"

if [ "$#" -gt 0 ]; then cases=("$@"); else
    cases=(); for f in "$suite_root"/traces/*.ndjson; do b="$(basename "$f" .ndjson)"; cases+=("$b"); done
fi

fail=0
: > "$summary.tmp"
for case_name in "${cases[@]}"; do
    trace="$suite_root/traces/$case_name.ndjson"
    log="output/v1-trace-$case_name.log"
    test -s "$trace" || { echo "MISSING $case_name" | tee -a "$summary.tmp"; fail=1; continue; }
    timeout "$timeout_bound" env SPECULA_TRACE="$trace" \
        java -XX:+UseParallelGC -cp "$classpath" tlc2.TLC -workers 1 -cleanup \
        -metadir "$run_state/$case_name" -config Trace.cfg Trace > "$log" 2>&1
    rc=$?
    rm -rf "$run_state/$case_name"
    records=$(wc -l < "$trace")
    if grep -q 'Model checking completed. No error has been found.' "$log" \
       && grep -q 'Checking temporal properties for the complete state space' "$log"; then
        echo "PASS $case_name records=$records rc=$rc $(grep -E 'distinct states found' "$log" | tail -1)" | tee -a "$summary.tmp"
    else
        echo "FAIL $case_name records=$records rc=$rc $(grep -E 'Error|violated' "$log" | head -2 | tr '\n' ' ')" | tee -a "$summary.tmp"
        fail=1
    fi
done
mv "$summary.tmp" "$summary"
exit $fail
