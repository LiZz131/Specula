#!/usr/bin/env bash
# Real TLC trace validation (Trace.tla + Trace.cfg, PROPERTIES TraceMatched) for each NDJSON
# trace given on the command line (default: every retained fresh trace). One TLC per trace,
# states under /dev/shm/specula-e2e-case-004/, logs in spec/output/trace-<name>.log.
set -uo pipefail
spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$spec_dir/.." && pwd)"
cp_jars=/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar
state_root=/dev/shm/specula-e2e-case-004
mkdir -p "$state_root" "$spec_dir/output"
if [ $# -eq 0 ]; then
    set -- "$root"/traces/*.ndjson "$root"/traces/core-*/*.ndjson
fi
summary="$spec_dir/output/trace-validation-summary.tsv"
pass=0; fail=0
for t in "$@"; do
    t="$(readlink -f "$t")"
    rel="${t#$root/}"
    name="$(echo "$rel" | sed 's|^traces/||; s|\.ndjson$||; s|/|__|g')"
    log="$spec_dir/output/trace-$name.log"
    meta="$state_root/trace-$name-$$"
    events=$(wc -l < "$t")
    ( cd "$spec_dir" && JSON="$t" timeout 10m java -XX:+UseParallelGC -cp "$cp_jars" tlc2.TLC -noGenerateSpecTE \
        -deadlock -workers 1 -metadir "$meta" -config Trace.cfg Trace.tla ) > "$log" 2>&1
    rc=$?
    rm -rf "$meta"
    if grep -q "Finished checking temporal properties" "$log" && \
       grep -q "Model checking completed. No error has been found." "$log"; then
        res=PASS; pass=$((pass+1))
    else
        res=FAIL; fail=$((fail+1))
    fi
    printf '%s\t%s\t%s\t%s\trc=%s\n' "$res" "$rel" "$events" "${log#$root/}" "$rc" | tee -a "$summary"
done
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
