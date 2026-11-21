#!/usr/bin/env bash
# Replay every retained fresh trace through Trace.tla with TLC (real trace
# validation; TraceConsumed temporal property enabled in Trace.cfg).
set -euo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
state_parent="/dev/shm/specula-e2e-case-011"
run_state="$state_parent/trace-$$"
timeout_bound="${SPECULA_TLC_TIMEOUT:-5m}"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
source "$suite_root/harness/cases.sh"
selected=("${@:-${cases[@]}}")
[ "$#" -gt 0 ] && selected=("$@") || selected=("${cases[@]}")

cleanup() { rm -rf "$run_state"; }
trap cleanup EXIT INT TERM
mkdir -p "$run_state"
cd "$spec_dir"

summary="$spec_dir/output/trace-validation-summary.txt"
: > "$summary"
fail=0
for case_name in "${selected[@]}"; do
    trace="$suite_root/traces/$case_name.ndjson"
    test -s "$trace"
    log="output/trace-$case_name.log"
    set +e
    timeout "$timeout_bound" env SPECULA_TRACE="$trace" \
        java -XX:+UseParallelGC -cp "$classpath" tlc2.TLC -workers 1 -cleanup \
        -metadir "$run_state/$case_name" -config Trace.cfg Trace > "$log" 2>&1
    rc=$?
    set -e
    rm -rf "$run_state/$case_name"
    events=$(wc -l < "$trace")
    if grep -q 'Model checking completed. No error has been found.' "$log" \
       && grep -q 'Checking temporal properties for the complete state space' "$log"; then
        echo "PASS $case_name events=$events $(grep -E 'distinct states found' "$log" | tail -1)" | tee -a "$summary"
    else
        echo "FAIL $case_name events=$events rc=$rc" | tee -a "$summary"
        fail=1
    fi
done
exit $fail
