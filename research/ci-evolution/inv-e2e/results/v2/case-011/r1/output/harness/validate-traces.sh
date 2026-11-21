#!/usr/bin/env bash
# Replay every fresh trace with Trace.tla (TraceConsumed temporal property +
# post/pre-state checks). One TLC run per trace; states under /dev/shm.
set -uo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
state_parent="/dev/shm/specula-e2e-case-011"
run_state="$state_parent/trace-$$"
timeout_bound="${SPECULA_TLC_TIMEOUT:-5m}"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
summary="$spec_dir/output/trace-validation-summary.txt"

if [ "$#" -gt 0 ]; then cases=("$@"); else
    cases=()
    for f in "$suite_root"/traces/*.ndjson; do cases+=("$(basename "$f" .ndjson)"); done
fi

cleanup() { rm -rf "$run_state"; }
trap cleanup EXIT INT TERM
mkdir -p "$run_state"
cd "$spec_dir"
: > "$summary"
fail=0
for case_name in "${cases[@]}"; do
    trace="$suite_root/traces/$case_name.ndjson"
    test -s "$trace" || { echo "$case_name MISSING" | tee -a "$summary"; fail=1; continue; }
    log="output/trace-$case_name.log"
    timeout "$timeout_bound" env SPECULA_TRACE="$trace" \
        java -XX:+UseParallelGC -cp "$classpath" tlc2.TLC -workers 1 \
        -metadir "$run_state/$case_name" -config Trace.cfg Trace > "$log" 2>&1
    rc=$?
    rm -rf "$run_state/$case_name"
    events=$(wc -l < "$trace")
    if grep -q 'Model checking completed. No error has been found.' "$log"; then
        states=$(grep -o '[0-9,]* distinct states found' "$log" | tail -1)
        echo "$case_name PASS events=$events ($states) rc=$rc" | tee -a "$summary"
    else
        echo "$case_name FAIL events=$events rc=$rc" | tee -a "$summary"; fail=1
    fi
done
exit $fail
