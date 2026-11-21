#!/usr/bin/env bash
# Run real TLC trace validation of one fresh trace against Trace.tla/Trace.cfg.
# Usage: scripts/trace_validate.sh <trace-name> [log-suffix]
# State directory under /dev/shm/specula-e2e-case-012/, removed after the run.
set -uo pipefail
spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="$1"; suffix="${2:-}"; cfg="${TRACE_CFG:-Trace.cfg}"
trace="$spec_dir/../traces/$name.ndjson"
log="$spec_dir/output/trace-$name${suffix}.log"
meta="/dev/shm/specula-e2e-case-012/trace-$name-$$"
mkdir -p "$meta"
CP=/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar
cd "$spec_dir"
echo "# cmd: JSON=$trace java -cp $CP tlc2.TLC -config $cfg -deadlock -workers 1 -metadir $meta Trace.tla" > "$log"
JSON="$trace" timeout 600 java -XX:+UseParallelGC -Xmx4g -cp "$CP" tlc2.TLC -config "$cfg" \
    -deadlock -workers 1 -metadir "$meta" Trace.tla >> "$log" 2>&1
rc=$?
echo "# exit=$rc" >> "$log"
rm -rf "$meta"
if grep -q "Model checking completed. No error has been found" "$log" && [ $rc -eq 0 ]; then
    echo "$name: PASS ($(grep -E 'distinct states found' "$log" | tail -1))"
else
    echo "$name: FAIL rc=$rc ($(grep -E '^Error|violated|Temporal properties' "$log" | head -2 | tr '\n' ' '))"
fi
