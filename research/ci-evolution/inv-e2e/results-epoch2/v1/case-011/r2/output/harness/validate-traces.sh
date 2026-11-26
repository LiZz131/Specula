#!/usr/bin/env bash
# Real TLC trace validation of every retained fresh trace against Trace.tla.
# Usage: validate-traces.sh [case ...]   (default: every traces/*.ndjson)
set -uo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
state_parent="/dev/shm/specular-e2e-case-011"
run_state="$state_parent/trace-$$"
timeout_bound="${SPECULAR_TLC_TIMEOUT:-5m}"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
summary="$spec_dir/output/trace-validation-summary.tsv"

cleanup() { rm -rf "$run_state"; }
trap cleanup EXIT INT TERM
mkdir -p "$run_state" "$spec_dir/output"
cd "$spec_dir"

if [ "$#" -gt 0 ]; then cases=("$@"); else
    cases=(); for f in "$suite_root"/traces/*.ndjson; do cases+=("$(basename "$f" .ndjson)"); done
fi

fail=0
: > "$summary.tmp"
for case_name in "${cases[@]}"; do
    trace="$suite_root/traces/$case_name.ndjson"
    log="output/trace-$case_name.log"
    test -s "$trace" || { echo "missing $trace"; fail=1; continue; }
    timeout "$timeout_bound" env SPECULAR_TRACE="$trace" \
        java -XX:+UseParallelGC -cp "$classpath" tlc2.TLC -workers 1 -deadlock \
        -metadir "$run_state/$case_name" -config Trace.cfg Trace > "$log" 2>&1
    rc=$?
    rm -rf "$run_state/$case_name"
    events=$(wc -l < "$trace")
    if grep -q 'Model checking completed. No error has been found.' "$log" \
       && grep -q 'Checking temporal properties for the complete state space' "$log"; then
        status=PASS
    else
        status=FAIL; fail=1
    fi
    states=$(grep -oE '[0-9,]+ distinct states found' "$log" | tail -1)
    printf '%s\t%s\tevents=%s\trc=%s\t%s\t%s\n' "$case_name" "$status" "$events" "$rc" "$states" "$log" | tee -a "$summary.tmp"
done
mv "$summary.tmp" "$summary"
exit $fail
