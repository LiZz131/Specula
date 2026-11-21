#!/usr/bin/env bash
# Bounded TLC campaign runner.
# Usage: run-model-check.sh <module> <cfg> <bfs|sim> <minutes> <workers> <tag> [extra TLC args...]
# States live under /dev/shm/specula-e2e-case-011/ and are removed after the run;
# logs go to spec/output/v1-mc-<tag>.log. A run stopped by the outer time bound
# is BUDGET-LIMITED exploration (LIMITED_COVERAGE), never a proof.
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
module="$1"; cfg="$2"; mode="$3"; minutes="$4"; workers="$5"; tag="$6"; shift 6
spec_dir="$suite_root/spec"
state="/dev/shm/specula-e2e-case-011/$tag-$$"
log="$spec_dir/output/v1-mc-$tag.log"
heap="${SPECULA_TLC_HEAP:-12g}"
cp="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
cleanup() { rm -rf "$state"; }
trap cleanup EXIT INT TERM
mkdir -p "$state" "$spec_dir/output"
cd "$spec_dir"
args=(-workers "$workers" -metadir "$state" -config "$cfg")
if [ "$mode" = sim ]; then args+=(-simulate "num=999999999" -depth "${SPECULA_SIM_DEPTH:-100}"); fi
cmd=(java -Xmx"$heap" -XX:+UseParallelGC -cp "$cp" tlc2.TLC "${args[@]}" "$@" "$module")
{
  echo "# command: timeout ${minutes}m ${cmd[*]}"
  echo "# started: $(date -Is)"
} > "$log"
timeout --signal=TERM "${minutes}m" "${cmd[@]}" >> "$log" 2>&1
rc=$?
echo "# exit: $rc ($( [ $rc -eq 124 ] && echo 'outer time bound reached: BUDGET-LIMITED' || echo 'TLC terminated'))" >> "$log"
echo "# finished: $(date -Is)" >> "$log"
exit 0
