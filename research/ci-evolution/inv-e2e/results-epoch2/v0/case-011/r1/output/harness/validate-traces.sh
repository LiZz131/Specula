#!/usr/bin/env bash
# Replay every fresh trace with Trace.tla (TraceSpec + TraceConsumed).
set -euo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
state_parent="/dev/shm/specula-e2e-case-011"
run_state="$state_parent/trace-$$"
timeout_bound="${SPECULA_TLC_TIMEOUT:-5m}"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
suffix="${SPECULA_LOG_SUFFIX:-}"
if [ "$#" -gt 0 ]; then cases=("$@"); else mapfile -t cases < <(grep -vE '^\s*(#|$)' "$suite_root/harness/cases.txt"); fi

cleanup() { rm -rf "$run_state"; }
trap cleanup EXIT INT TERM
mkdir -p "$run_state"
cd "$spec_dir"
fail=0
for case_name in "${cases[@]}"; do
    log="output/trace-$case_name$suffix.log"
    test -s "$suite_root/traces/$case_name.ndjson"
    set +e
    timeout "$timeout_bound" env SPECULA_TRACE="$suite_root/traces/$case_name.ndjson" \
        java -XX:+UseParallelGC -cp "$classpath" tlc2.TLC -workers 1 -cleanup \
        -metadir "$run_state/$case_name" -config Trace.cfg Trace > "$log" 2>&1
    set -e
    rm -rf "$run_state/$case_name"
    events=$(wc -l < "$suite_root/traces/$case_name.ndjson")
    if grep -q 'Model checking completed. No error has been found.' "$log" \
       && grep -q 'Checking temporal properties for the complete state space' "$log"; then
        echo "PASS $case_name events=$events"
    else
        echo "FAIL $case_name events=$events (see spec/$log)"; fail=1
    fi
done
exit $fail
