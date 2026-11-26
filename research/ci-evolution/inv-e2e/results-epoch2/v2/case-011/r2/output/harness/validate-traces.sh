#!/usr/bin/env bash
# Real TLC trace validation of every retained fresh trace against Trace.tla.
# Usage: validate-traces.sh [case ...]   (default: every traces/*.ndjson except archived-v0)
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
state_root="/dev/shm/specular-e2e-case-011"
run_state="$state_root/trace-$$"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
if [ $# -gt 0 ]; then cases=("$@"); else
  cases=(); for f in "$suite_root"/traces/*.ndjson; do b=$(basename "$f" .ndjson); cases+=("$b"); done
fi
cleanup() { rm -rf "$run_state"; }
trap cleanup EXIT INT TERM
mkdir -p "$run_state" "$spec_dir/output"
cd "$spec_dir"
fail=0
for case_name in "${cases[@]}"; do
    trace="$suite_root/traces/$case_name.ndjson"
    log="output/trace-$case_name.log"
    test -s "$trace" || { echo "MISSING $trace"; fail=1; continue; }
    echo "# command: SPECULAR_TRACE=$trace java tlc2.TLC -workers 1 -metadir $run_state/$case_name -config Trace.cfg Trace" > "$log"
    timeout 10m env SPECULAR_TRACE="$trace" \
        java -XX:+UseParallelGC -cp "$classpath" tlc2.TLC -workers 1 \
        -metadir "$run_state/$case_name" -config Trace.cfg Trace >> "$log" 2>&1
    rc=$?
    events=$(wc -l < "$trace")
    if [ $rc -eq 0 ] && grep -q 'Model checking completed. No error has been found.' "$log" \
       && grep -q 'Checking temporal properties for the complete state space' "$log"; then
        echo "PASS $case_name events=$events $(grep -o '[0-9,]* distinct states found' "$log" | tail -1)"
    else
        echo "FAIL $case_name events=$events rc=$rc"; fail=1
    fi
    rm -rf "$run_state/$case_name"
done
exit $fail
