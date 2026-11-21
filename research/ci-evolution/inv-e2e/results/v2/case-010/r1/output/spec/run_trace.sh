#!/usr/bin/env bash
# Usage: run_trace.sh <trace.ndjson> <log-name> [cfg]
set -uo pipefail
cd /work/current/.specula-output/spec
TRACE=$(readlink -f "$1"); NAME=$2; CFG=${3:-Trace.cfg}; MODULE=${4:-Trace}
META=/dev/shm/specula-e2e-case-010/trace-$NAME-$$
mkdir -p "$META" output
JSON="$TRACE" timeout 10m java -XX:+UseParallelGC -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar \
  tlc2.TLC -workers 1 -metadir "$META" -config "$CFG" "$MODULE.tla" > "output/trace-$NAME.log" 2>&1
RC=$?
rm -rf "$META"
echo "$NAME rc=$RC"; grep -E "Error|violated|distinct states|Finished|Exception" "output/trace-$NAME.log" | head -8
