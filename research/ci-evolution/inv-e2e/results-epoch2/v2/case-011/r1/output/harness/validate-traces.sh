#!/usr/bin/env bash
# Replay every fresh trace (or the ones given as arguments) against Trace.tla
# with real TLC, TraceConsumed as temporal completion property, and all
# Trace.cfg invariants. States live under /dev/shm/specula-e2e-case-011 and
# are removed after each run; logs go to spec/output/trace-<name>.log.
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
state_parent="/dev/shm/specula-e2e-case-011"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
timeout_bound="${SPECULA_TLC_TIMEOUT:-5m}"
tag="${SPECULA_TRACE_TAG:-}"
if [ "$#" -gt 0 ]; then names=("$@"); else
    names=(); for f in "$suite_root"/traces/*.ndjson; do names+=("$(basename "$f" .ndjson)"); done; fi
mkdir -p "$state_parent" "$spec_dir/output"
one() {
    local name="$1"; local meta="$state_parent/trace-$name-$$"
    local log="$spec_dir/output/trace-$name$tag.log"
    ( cd "$spec_dir" && echo "COMMAND: cd $spec_dir && SPECULA_TRACE=$suite_root/traces/$name.ndjson timeout $timeout_bound java -XX:+UseParallelGC -cp $classpath tlc2.TLC -workers 1 -metadir $meta -noGenerateSpecTE -config Trace.cfg Trace" > "$log"
      timeout "$timeout_bound" env SPECULA_TRACE="$suite_root/traces/$name.ndjson" \
        java -XX:+UseParallelGC -cp "$classpath" tlc2.TLC -workers 1 -metadir "$meta" -noGenerateSpecTE \
        -config Trace.cfg Trace >> "$log" 2>&1 ; echo "EXIT=$?" >> "$log" )
    rm -rf "$meta"
    if grep -q 'Model checking completed. No error has been found.' "$log" \
       && grep -q 'Checking temporal properties for the complete state space' "$log"; then
        echo "PASS $name $(grep -oE '[0-9]+ distinct states found' "$log" | head -1)"
    else
        echo "FAIL $name: $(grep -E 'Error|violated|is not|Temporal' "$log" | head -2 | tr '\n' ' ')"
    fi
}
export -f one; export spec_dir suite_root state_parent classpath timeout_bound tag
printf '%s\n' "${names[@]}" | xargs -P 8 -I{} bash -c 'one {}' | sort
