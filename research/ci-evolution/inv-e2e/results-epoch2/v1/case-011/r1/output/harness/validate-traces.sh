#!/usr/bin/env bash
# Replay every fresh new-version trace with TLC against Trace.tla/Trace.cfg.
# Success requires TLC to finish with "No error has been found" AND the
# TraceConsumed temporal property to have been checked (cursor reaches the end).
set -uo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
state_parent="/dev/shm/specula-e2e-case-011"
run_state="$state_parent/trace-$$"
timeout_bound="${SPECULA_TLC_TIMEOUT:-5m}"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
suffix="${SPECULA_LOG_SUFFIX:-}"
if [ "$#" -gt 0 ]; then cases=("$@"); else
  cases=($(cd "$suite_root/traces" && ls *.ndjson | sed 's/\.ndjson$//'))
fi

cleanup() { rm -rf "$run_state"; }
trap cleanup EXIT INT TERM
mkdir -p "$run_state" "$spec_dir/output"
cd "$spec_dir"

pass=0; fail=0; failed=()
for case_name in "${cases[@]}"; do
    trace="$suite_root/traces/$case_name.ndjson"
    log="output/trace-$case_name$suffix.log"
    test -s "$trace" || { echo "MISSING $trace"; fail=$((fail+1)); failed+=("$case_name"); continue; }
    echo "cmd: SPECULA_TRACE=$trace java -cp $classpath tlc2.TLC -workers 1 -metadir $run_state/$case_name -config Trace.cfg Trace" > "$log"
    timeout "$timeout_bound" env SPECULA_TRACE="$trace" \
        java -XX:+UseParallelGC -cp "$classpath" tlc2.TLC -noGenerateSpecTE -workers 1 \
        -metadir "$run_state/$case_name" -config Trace.cfg Trace >> "$log" 2>&1
    rm -rf "$run_state/$case_name"
    if grep -q 'Model checking completed. No error has been found.' "$log" \
       && grep -q 'Checking temporal properties for the complete state space' "$log"; then
        pass=$((pass+1)); echo "PASS $case_name ($(wc -l < "$trace") events)"
    else
        fail=$((fail+1)); failed+=("$case_name"); echo "FAIL $case_name -> $log"
    fi
done
echo "trace validation: $pass passed, $fail failed ${failed[*]:-}"
[ "$fail" -eq 0 ]
