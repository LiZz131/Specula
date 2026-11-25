#!/usr/bin/env bash
# Real TLC trace validation of every retained fresh trace (TraceConsumed
# temporal property + post-state checks). States under /dev/shm, removed after.
set -euo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
state_parent="/dev/shm/specular-e2e-case-011"
run_state="$state_parent/trace-$$"
timeout_bound="${SPECULAR_TLC_TIMEOUT:-5m}"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
source "$suite_root/harness/cases.sh"
summary="$spec_dir/output/trace-validation-summary.txt"

cleanup() { rm -rf "$run_state"; }
trap cleanup EXIT INT TERM
mkdir -p "$run_state"
cd "$spec_dir"
: > "$summary"
fail=0
for case_name in "${cases[@]}"; do
    trace="$suite_root/traces/$case_name.ndjson"
    test -s "$trace"
    log="output/trace-$case_name.log"
    timeout "$timeout_bound" env SPECULAR_TRACE="$trace" \
        java -XX:+UseParallelGC -cp "$classpath" tlc2.TLC -workers 1 -cleanup \
        -metadir "$run_state/$case_name" -config Trace.cfg Trace > "$log" 2>&1 || true
    rm -rf "$run_state/$case_name"
    events=$(wc -l < "$trace")
    if grep -q 'Model checking completed. No error has been found.' "$log"; then
        echo "PASS $case_name events=$events $(grep -o '[0-9]* distinct states found' "$log" | head -1)" | tee -a "$summary"
    else
        echo "FAIL $case_name events=$events" | tee -a "$summary"; fail=1
    fi
done
exit $fail
