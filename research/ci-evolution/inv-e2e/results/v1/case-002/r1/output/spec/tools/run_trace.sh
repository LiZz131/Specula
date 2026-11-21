#!/usr/bin/env bash
# Usage: run_trace.sh <trace-name> <log-tag> [cfg]   (run from spec/)
set -uo pipefail
name="$1"; tag="$2"; cfg="${3:-Trace.cfg}"
meta="/dev/shm/specula-e2e-case-002/trace-$tag-$(basename $name)-$$"
log="output/trace-$tag-$(basename $name).log"
mkdir -p "$meta"
cmd=(timeout 1800s env JSON="../traces/$name.ndjson" java -Xmx12g -XX:+UseParallelGC
     -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC
     -cleanup -workers ${WORKERS:-8} -config "$cfg" -metadir "$meta" "${MODULE:-Trace}.tla")
{ echo "# cwd: $(pwd)"; echo "# cmd: ${cmd[*]}"; echo "# trace sha256: $(sha256sum ../traces/$name.ndjson | cut -c1-64)"; echo "# events: $(grep -c '"tag":"trace"' ../traces/$name.ndjson)"; } > "$log"
"${cmd[@]}" >> "$log" 2>&1
rc=$?
echo "# exit: $rc" >> "$log"
rm -rf "$meta"
echo "$name rc=$rc $(grep -E 'No error has been found|Error:|violated|distinct states found' "$log" | head -3 | tr '\n' ' ')"
