#!/usr/bin/env bash
# Real TLC trace validation of every fresh trace (Trace.tla + Trace.cfg, TraceMatched).
# Usage: ./run_trace_validation.sh [trace.ndjson ...]   (default: ../traces/*.ndjson)
set -uo pipefail
cd "$(dirname "$0")"
LIB=/work/lib
STATES=/dev/shm/specula-e2e-case-004
mkdir -p output "$STATES"
traces=("$@"); [ ${#traces[@]} -eq 0 ] && traces=(../traces/*.ndjson)
run_one() {
  local t="$1" name; name="$(basename "$t" .ndjson)"
  local meta="$STATES/trace-$name-$$"
  JSON="$(cd "$(dirname "$t")" && pwd)/$(basename "$t")" timeout 10m java -XX:+UseParallelGC -Xmx2g \
     -cp "$LIB/tla2tools.jar:$LIB/CommunityModules-deps.jar" tlc2.TLC -config Trace.cfg -deadlock \
     -workers 1 -metadir "$meta" Trace.tla > "output/trace-$name.log" 2>&1
  local rc=$?
  rm -rf "$meta"
  if grep -q "Model checking completed. No error has been found." "output/trace-$name.log" \
     && grep -q "Finished checking temporal properties" "output/trace-$name.log"; then
    echo "PASS $name (lines=$(wc -l < "$t"))"
  else
    echo "FAIL $name rc=$rc"
  fi
}
export -f run_one; export LIB STATES
printf '%s\n' "${traces[@]}" | xargs -P 8 -I{} bash -c 'run_one "$@"' _ {} | sort
