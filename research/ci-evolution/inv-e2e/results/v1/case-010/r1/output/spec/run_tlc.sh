#!/usr/bin/env bash
# usage: run_tlc.sh <cfg> <module> <minutes> <workers> <label> [extra TLC args...]
set -u
cfg=$1; mod=$2; mins=$3; w=$4; label=$5; shift 5
cd "$(dirname "$0")"
meta=/dev/shm/specula-e2e-case-010/${label}-$$
log=output/${label}.log
mkdir -p output /dev/shm/specula-e2e-case-010
echo "CMD: timeout $((mins*60+120))s java -XX:+UseParallelGC -Xmx${XMX:-16g} -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -workers $w -metadir $meta -config $cfg $* $mod  (TLC wall limit ${mins}m via outer timeout)" > "$log"
echo "START: $(date -u +%FT%TZ)" >> "$log"
timeout -s TERM $((mins*60)) java -XX:+UseParallelGC -Xmx${XMX:-16g} -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -workers "$w" -metadir "$meta" -config "$cfg" "$@" "$mod" >> "$log" 2>&1
rc=$?
echo "END: $(date -u +%FT%TZ) exit=$rc$( [ $rc -eq 124 ] && echo ' (TIME LIMIT REACHED: LIMITED_COVERAGE)')" >> "$log"
rm -rf "$meta"
echo "$label exit=$rc"
