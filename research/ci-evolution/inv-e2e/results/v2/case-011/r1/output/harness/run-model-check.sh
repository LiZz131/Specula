#!/usr/bin/env bash
# Run one bounded TLC campaign.
# usage: run-model-check.sh <name> <module> <cfg> <bfs|sim> <minutes> <workers> [heapGB] [depth]
# States go under /dev/shm/specula-e2e-case-011/<name>-<pid> and are removed afterwards;
# the log is spec/output/mc-<name>.log. TLC's own -maxSetSize is default.
set -uo pipefail
name="$1"; module="$2"; cfg="$3"; mode="$4"; minutes="$5"; workers="$6"; heap="${7:-16}"; depth="${8:-60}"
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
state_dir="/dev/shm/specula-e2e-case-011/$name-$$"
log="$spec_dir/output/mc-$name.log"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
cleanup() { rm -rf "$state_dir"; }
trap cleanup EXIT INT TERM
mkdir -p "$state_dir"
cd "$spec_dir"
if [ "$mode" = sim ]; then
    modeargs=(-simulate num=999999999 -depth "$depth")
else
    modeargs=()
fi
# Bounded counters make terminal states normal in focused/open specs (no always-enabled
# refresh action); SPECULA_NODEADLOCK=1 disables TLC deadlock reporting for those runs.
if [ "${SPECULA_NODEADLOCK:-0}" = 1 ]; then modeargs+=(-deadlock); fi
{
  echo "# campaign=$name module=$module cfg=$cfg mode=$mode budget=${minutes}m workers=$workers heap=${heap}G depth=$depth nodeadlock=${SPECULA_NODEADLOCK:-0}"
  echo "# started $(date -Is)"
} > "$log"
# Outer timeout = planned exploration budget (+1 minute grace for shutdown).
timeout --signal=TERM "$((minutes * 60 + 60))s" \
  java -Xmx"${heap}g" -XX:+UseParallelGC -Dtlc2.TLC.stopAfter=$((minutes * 60)) \
       -cp "$classpath" tlc2.TLC -workers "$workers" -metadir "$state_dir" -coverage 5 \
       "${modeargs[@]}" -config "$cfg" "$module" >> "$log" 2>&1
rc=$?
echo "# finished $(date -Is) rc=$rc" >> "$log"
exit $rc
