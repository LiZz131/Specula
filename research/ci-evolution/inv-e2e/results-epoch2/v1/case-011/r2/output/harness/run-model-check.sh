#!/usr/bin/env bash
# Bounded TLC run. Usage: run-model-check.sh <Spec> <cfg> <label> [minutes] [workers] [extra TLC args...]
# States live under /dev/shm/specular-e2e-case-011/<label>-<pid> and are removed on exit;
# the log is spec/output/mc-<label>.log.
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec="$1"; cfg="$2"; label="$3"; minutes="${4:-30}"; workers="${5:-8}"; shift 5 2>/dev/null || shift $#
state="/dev/shm/specular-e2e-case-011/$label-$$"
log="$suite_root/spec/output/mc-$label.log"
heap="${SPECULAR_TLC_HEAP:-12g}"
cleanup() { rm -rf "$state"; }
trap cleanup EXIT INT TERM
mkdir -p "$state"
cd "$suite_root/spec"
{
  echo "# command: timeout $((minutes + 5))m java -Xmx$heap -XX:+UseParallelGC tlc2.TLC -workers $workers -deadlock -coverage 10 -metadir $state -config $cfg $spec $* (TLC -timeout via -Dtlc2.TLC.stopAfter=$((minutes*60)))"
  echo "# started: $(date -Is)"
} > "$log"
timeout "$((minutes + 5))m" java -Xmx"$heap" -XX:+UseParallelGC -Dtlc2.TLC.stopAfter=$((minutes * 60)) \
    -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC \
    -workers "$workers" -deadlock -coverage 10 -metadir "$state" -config "$cfg" "$@" "$spec" >> "$log" 2>&1
rc=$?
echo "# finished: $(date -Is) rc=$rc" >> "$log"
exit $rc
