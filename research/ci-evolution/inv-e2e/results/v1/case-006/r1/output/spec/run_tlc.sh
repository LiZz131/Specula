#!/usr/bin/env bash
# Bounded TLC runner for the incremental campaigns.
#   run_tlc.sh NAME MODULE CFG SECONDS WORKERS HEAP [extra TLC args...]
# Log: spec/output/mc/NAME.log; counterexample (if any): NAME.cex.json;
# TLC states: /dev/shm/specula-e2e-case-006/NAME-<pid> (removed afterwards).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
NAME="$1"; MODULE="$2"; CFG="$3"; SECS="$4"; WORKERS="$5"; HEAP="$6"; shift 6
STATE_ROOT="/dev/shm/specula-e2e-case-006"
META="$STATE_ROOT/${NAME}-$$"
LOG="output/mc/${NAME}.log"
mkdir -p "$META" output/mc
echo "# cmd: run_tlc.sh $NAME $MODULE $CFG $SECS $WORKERS $HEAP $*" > "$LOG"
echo "# start: $(date -Is)" >> "$LOG"
timeout --kill-after=60 $((SECS + 300)) java -Xmx"$HEAP" -XX:+UseParallelGC \
  -Dtlc2.TLC.stopAfter="$SECS" \
  -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC \
  -workers "$WORKERS" -metadir "$META" -noGenerateSpecTE \
  -dumpTrace json "output/mc/${NAME}.cex.json" \
  -config "$CFG" "$@" "$MODULE" >> "$LOG" 2>&1
RC=$?
rm -rf "${META:?}"
rmdir "$STATE_ROOT" 2>/dev/null || true
echo "# end: $(date -Is) rc=$RC" >> "$LOG"
V=$(grep -E "^Error: (Invariant|Action property|Temporal|The property)" "$LOG" | head -1)
D=$(grep -E "^Model checking completed|^The depth of the complete state graph|states generated|Stopping after|stopAfter|^Progress" "$LOG" | tail -3 | tr '\n' ' ')
echo "$NAME rc=$RC ${V:-no-violation} :: $D" | tee "output/mc/${NAME}.summary"
