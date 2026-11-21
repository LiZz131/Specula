#!/usr/bin/env bash
# Bounded TLC runner for Specula campaigns.
# usage: run-tlc.sh <Module> <cfg> <label> <stop-after-seconds> [extra TLC args...]
# - states under /dev/shm/specula-e2e-case-011/<label>-<pid> (removed afterwards)
# - log in spec/output/mc-<label>.log
# - graceful stop via -Dtlc2.TLC.stopAfter, plus an outer timeout guard
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
module="$1"; cfg="$2"; label="$3"; stop_after="$4"; shift 4
state_dir="/dev/shm/specula-e2e-case-011/$label-$$"
log="$suite_root/spec/output/mc-$label.log"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
heap="${SPECULA_TLC_HEAP:-24g}"
workers="${SPECULA_TLC_WORKERS:-12}"
trap 'rm -rf "$state_dir"' EXIT INT TERM
mkdir -p "$state_dir"
cd "$suite_root/spec"
{
  echo "# command: java -Xmx$heap -Dtlc2.TLC.stopAfter=$stop_after tlc2.TLC -workers $workers -metadir $state_dir -config $cfg $* $module"
  echo "# started: $(date -u +%FT%TZ)"
} > "$log"
timeout $((stop_after + 600)) java -Xmx"$heap" -XX:+UseParallelGC -Dtlc2.TLC.stopAfter="$stop_after" \
    -cp "$classpath" tlc2.TLC -workers "$workers" -metadir "$state_dir" -config "$cfg" "$@" "$module" >> "$log" 2>&1
rc=$?
echo "# exit: $rc finished: $(date -u +%FT%TZ)" >> "$log"
rm -rf "$state_dir"
rm -f "$suite_root/spec/${module}_TTrace_"*.tla 2>/dev/null
exit $rc
