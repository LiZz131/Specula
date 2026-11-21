#!/usr/bin/env bash
# Replay fresh traces against Trace.tla with real TLC (TraceMatched temporal
# property + post-state checks). Usage: run_trace_validation.sh <tag> [trace...]
set -uo pipefail
spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tag="$1"; shift
lib=/work/lib
states_root=/dev/shm/specula-e2e-case-012
mkdir -p "$states_root" "$spec_dir/output"
traces=("$@")
if [ ${#traces[@]} -eq 0 ]; then traces=("$spec_dir"/../traces/*.ndjson); fi
summary="$spec_dir/output/trace-validation-$tag.summary"
: > "$summary"
for t in "${traces[@]}"; do
    name="$(basename "$t" .ndjson)"
    cfg=Trace.cfg
    case "$name" in update_effective_learner) cfg=Trace_fixture.cfg ;; esac
    meta="$states_root/trace-$tag-$name"
    log="$spec_dir/output/trace-$tag-$name.log"
    rm -rf "$meta"
    ( cd "$spec_dir" && JSON="$(readlink -f "$t")" timeout 600 java -XX:+UseParallelGC -Xmx4g \
        -cp "$lib/tla2tools.jar:$lib/CommunityModules-deps.jar" tlc2.TLC \
        -config "$cfg" -metadir "$meta" -workers 1 -cleanup Trace.tla ) > "$log" 2>&1
    rc=$?
    rm -rf "$meta"
    events=$(wc -l < "$t")
    if [ $rc -eq 0 ] && grep -q "Model checking completed. No error has been found." "$log"; then
        res=PASS
    else
        res=FAIL
    fi
    states=$(grep -oE "[0-9]+ distinct states found" "$log" | tail -1)
    printf '%-45s %-17s events=%-3s rc=%-3s %s %s\n' "$name" "$cfg" "$events" "$rc" "$res" "$states" | tee -a "$summary"
done
