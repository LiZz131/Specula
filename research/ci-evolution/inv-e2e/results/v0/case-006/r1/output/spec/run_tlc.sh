#!/usr/bin/env bash
# Bounded TLC runner.  Usage:
#   run_tlc.sh <run-name> <Module.tla> <cfg> <minutes> <workers> [extra TLC args...]
# Writes spec/output/<run-name>.log (+ .cex.json when a trace is dumped).
# States live under /dev/shm/specula-e2e-case-006/<run-name> and are removed
# after the run.  The outer `timeout` is the planned exploration budget; a
# run stopped by it is recorded as LIMITED_COVERAGE, never as a pass.
set -uo pipefail
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
name=$1; module=$2; cfg=$3; minutes=$4; workers=$5; shift 5
TLA_CP="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
STATE_ROOT="/dev/shm/specula-e2e-case-006"
meta="$STATE_ROOT/$name"
log="$SPEC_DIR/output/$name.log"
mkdir -p "$meta" "$SPEC_DIR/output"
cd "$SPEC_DIR"
start=$(date -u +%FT%TZ)
{
  echo "# run=$name module=$module cfg=$cfg budget=${minutes}m workers=$workers extra=$* start=$start"
  echo "# cmd: timeout ${minutes}m java -Xmx20g -XX:+UseParallelGC -cp $TLA_CP tlc2.TLC -workers $workers -metadir $meta -noGenerateSpecTE -dumpTrace json output/$name.cex.json -config $cfg $* $module"
} > "$log"
timeout --signal=TERM "${minutes}m" java -Xmx20g -XX:+UseParallelGC -cp "$TLA_CP" tlc2.TLC \
    -workers "$workers" -metadir "$meta" -noGenerateSpecTE \
    -dumpTrace json "output/$name.cex.json" -config "$cfg" "$@" "$module" >> "$log" 2>&1
rc=$?
find "$meta" -depth -delete 2>/dev/null; rmdir "$STATE_ROOT" 2>/dev/null || true
if [ $rc -eq 124 ]; then outcome="LIMITED_COVERAGE (planned ${minutes}m budget reached; queue not exhausted)"
elif grep -q "Model checking completed. No error has been found" "$log"; then outcome="EXHAUSTED_NO_ERROR"
elif grep -q "^Error:" "$log"; then outcome="VIOLATION_OR_ERROR: $(grep -m1 '^Error:' "$log")"
else outcome="OTHER rc=$rc"; fi
echo "# end=$(date -u +%FT%TZ) rc=$rc outcome=$outcome" >> "$log"
echo "$name: $outcome"
