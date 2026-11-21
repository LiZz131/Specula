#!/usr/bin/env bash
# Real TLC trace validation (TraceSpec + temporal TraceMatched + TypeOK/MembershipOrder)
# for every fresh trace (or the ones named on the command line).
# Usage: harness/validate_traces.sh [tag] [trace-name ...]
set -uo pipefail
out_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$out_dir/spec"
tag="${1:-run}"; shift || true
states_root="/dev/shm/specula-e2e-case-012"
cp="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
mkdir -p "$states_root" "$spec_dir/output"
if [ "$#" -gt 0 ]; then names=("$@"); else
  names=(); for f in "$out_dir"/traces/*.ndjson; do names+=("$(basename "$f" .ndjson)"); done; fi
summary="$spec_dir/output/trace-validation-$tag-summary.txt"
: > "$summary"
for name in "${names[@]}"; do
  trace="$out_dir/traces/$name.ndjson"
  log="$spec_dir/output/trace-$name-$tag.log"
  meta="$states_root/trace-$name-$tag"
  rm -rf "$meta"
  ( cd "$spec_dir" && JSON="$trace" timeout 600s java -XX:+UseParallelGC -Xmx4g -cp "$cp" tlc2.TLC \
      -config Trace.cfg -metadir "$meta" -workers 1 -cleanup Trace.tla ) > "$log" 2>&1
  rc=$?
  rm -rf "$meta"
  events=$(wc -l < "$trace")
  if grep -q "Model checking completed. No error has been found." "$log" && grep -q "Checking temporal properties" "$log"; then
    st="PASS"
  else
    st="FAIL"
  fi
  states=$(grep -oE "[0-9,]+ distinct states found" "$log" | tail -1)
  echo "$name events=$events rc=$rc result=$st ($states)" | tee -a "$summary"
done
