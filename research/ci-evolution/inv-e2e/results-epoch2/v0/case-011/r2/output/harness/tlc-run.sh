#!/usr/bin/env bash
# Bounded TLC run: tlc-run.sh MODULE CFG LOGNAME MINUTES WORKERS HEAP [extra TLC args...]
# States live under /dev/shm/specular-e2e-case-011/<run>; removed afterwards.
# The outer `timeout` is the planned exploration budget; a run stopped by it is
# recorded as budget-limited (LIMITED_COVERAGE), never as a pass.
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
module="$1"; cfg="$2"; logname="$3"; minutes="$4"; workers="$5"; heap="$6"; shift 6
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
state="/dev/shm/specular-e2e-case-011/${logname}-$$"
log="$suite_root/spec/output/$logname.log"
mkdir -p "$state"
cd "$suite_root/spec"
{
  echo "# command: timeout ${minutes}m java -Xmx$heap -XX:+UseParallelGC -cp $classpath tlc2.TLC -workers $workers -metadir $state -config $cfg $module $*"
  echo "# started: $(date -u +%FT%TZ)"
} > "$log"
timeout --signal=TERM "${minutes}m" java -Xmx"$heap" -XX:+UseParallelGC -cp "$classpath" tlc2.TLC \
    -workers "$workers" -metadir "$state" -config "$cfg" "$module" "$@" >> "$log" 2>&1
rc=$?
echo "# finished: $(date -u +%FT%TZ) rc=$rc$( [ $rc -eq 124 ] && echo ' (planned exploration budget reached: LIMITED_COVERAGE)')" >> "$log"
rm -rf "$state"
exit 0
