#!/usr/bin/env bash
# Bounded TLC runner for the incremental Specular run.
# Usage: tlc-run.sh <run-name> <Spec.tla> <Config.cfg> <minutes> [extra TLC args...]
#  - TLC states live under /dev/shm/specular-e2e-case-011/<run-name>-<pid> and are
#    removed when the run ends (success, violation, timeout, or signal).
#  - The log is written to spec/output/<run-name>.log.
#  - TLC stops itself after <minutes> (tlc2.TLC.stopAfter); an outer `timeout`
#    with a 5-minute grace protects against JVM hangs.
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
name="$1"; spec="$2"; cfg="$3"; minutes="$4"; shift 4
state_root="/dev/shm/specular-e2e-case-011"
metadir="$state_root/$name-$$"
log="$spec_dir/output/$name.log"
heap="${TLC_HEAP:-16g}"
workers="${TLC_WORKERS:-8}"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
mkdir -p "$metadir" "$spec_dir/output"
cleanup() { rm -rf "$metadir"; }
trap cleanup EXIT INT TERM
cd "$spec_dir"
{
  echo "# command: java -Xmx$heap -Dtlc2.TLC.stopAfter=$((minutes*60)) tlc2.TLC -workers $workers -deadlock -metadir $metadir -config $cfg $* $spec"
  echo "# started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$log"
timeout "$((minutes+5))m" java -Xmx"$heap" -XX:+UseParallelGC \
    -Dtlc2.TLC.stopAfter=$((minutes*60)) \
    -cp "$classpath" tlc2.TLC -workers "$workers" -deadlock \
    -metadir "$metadir" -config "$cfg" "$@" "$spec" >> "$log" 2>&1
rc=$?
echo "# exit: $rc finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log"
exit $rc
