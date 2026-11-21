#!/usr/bin/env bash
# Bounded TLC run.  Usage: ./run_tlc.sh <Module> <cfg> <label> <minutes> <workers> [bfs|sim] [extra TLC args...]
# States live under /dev/shm/specula-e2e-case-004/<label> and are removed afterwards.
set -uo pipefail
cd "$(dirname "$0")"
mod="$1"; cfg="$2"; label="$3"; mins="$4"; workers="$5"; mode="${6:-bfs}"; shift 6 || shift $#
LIB=/work/lib
meta="/dev/shm/specula-e2e-case-004/$label"
log="output/$label.log"
mkdir -p output "$meta"
extra=("$@")
simargs=()
[ "$mode" = sim ] && simargs=(-simulate num=999999999 -depth 100)
start=$(date +%s)
echo "CMD: timeout ${mins}m java -Xmx24g -XX:+UseParallelGC tlc2.TLC -config $cfg -workers $workers -deadlock -metadir $meta ${simargs[*]} ${extra[*]} $mod.tla" > "$log"
timeout --signal=TERM "${mins}m" java -Xmx24g -XX:+UseParallelGC -Dtlc2.TLC.stopAfter=$((mins*60)) \
  -cp "$LIB/tla2tools.jar:$LIB/CommunityModules-deps.jar" tlc2.TLC -config "$cfg" -workers "$workers" \
  -deadlock -metadir "$meta" "${simargs[@]}" "${extra[@]}" "$mod.tla" >> "$log" 2>&1
rc=$?
end=$(date +%s)
rm -rf "$meta"
echo "EXIT rc=$rc elapsed=$((end-start))s" >> "$log"
echo "== $label rc=$rc elapsed=$((end-start))s"
grep -E "Error:|violated|Model checking completed|states generated|The depth|Finished in|stopAfter|exceeded" "$log" | tail -8
