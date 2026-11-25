#!/usr/bin/env bash
# Usage: run-trace.sh <trace-name> <log-tag> [cfg]
# Real TLC trace validation (TraceMatched temporal property + post-state
# checks).  TLC state lives under /dev/shm/specula-e2e-case-002 and is
# removed after the run; the log is kept in spec/output/.
set -uo pipefail
spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
name="$1"; tag="$2"; cfg="${3:-Trace.cfg}"
trace="$spec_dir/../traces/$name.ndjson"
log="$spec_dir/output/trace-$tag-$name.log"
meta="/dev/shm/specula-e2e-case-002/trace-$tag-$name-$$"
mkdir -p "$meta" "$spec_dir/output"
cd "$spec_dir"
{
  echo "# command: JSON=$trace timeout 1800s java -XX:+UseParallelGC -Xmx8g -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -config $cfg -metadir $meta -workers 1 -cleanup Trace.tla"
  echo "# trace sha256: $(sha256sum "$trace" | cut -d' ' -f1) records: $(wc -l < "$trace")"
} > "$log"
JSON="$trace" timeout 1800s java -XX:+UseParallelGC -Xmx8g \
  -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar \
  tlc2.TLC -config "$cfg" -metadir "$meta" -workers 1 -cleanup Trace.tla >> "$log" 2>&1
rc=$?
echo "# exit: $rc" >> "$log"
rm -rf "$meta"
if grep -q "Model checking completed. No error has been found" "$log"; then
  echo "PASS $name ($(grep -o '[0-9,]* distinct states found' "$log" | tail -1))"
else
  echo "FAIL $name rc=$rc"; grep -m5 -E "Error|violated|Temporal|line [0-9]+, col" "$log"
fi
exit $rc
