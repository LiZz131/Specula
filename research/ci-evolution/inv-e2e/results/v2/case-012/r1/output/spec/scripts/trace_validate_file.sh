#!/usr/bin/env bash
# Like trace_validate.sh but takes an explicit trace path and log path.
set -uo pipefail
spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
trace="$1"; log="$2"; cfg="${TRACE_CFG:-Trace.cfg}"; module="${TRACE_MODULE:-Trace.tla}"
meta="/dev/shm/specula-e2e-case-012/tracef-$$-$(basename "$trace" .ndjson)"
mkdir -p "$meta"
CP=/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar
cd "${TRACE_DIR:-$spec_dir}"
echo "# cmd: JSON=$trace java -cp $CP tlc2.TLC -config $cfg -deadlock -workers 1 -metadir $meta $module (cwd $(pwd))" > "$log"
JSON="$trace" timeout 600 java -XX:+UseParallelGC -Xmx4g -cp "$CP" tlc2.TLC -config "$cfg" -deadlock -workers 1 -metadir "$meta" "$module" >> "$log" 2>&1
rc=$?; echo "# exit=$rc" >> "$log"; rm -rf "$meta"
if grep -q "Model checking completed. No error has been found" "$log" && [ $rc -eq 0 ]; then echo "$(basename "$trace"): PASS"; else echo "$(basename "$trace"): REJECTED rc=$rc ($(grep -E '^Error|violated' "$log" | head -1))"; fi
