#!/usr/bin/env bash
# Bounded TLC run: run_tlc.sh <Module> <cfg> <tag> <minutes> <workers> [extra TLC args...]
# States under /dev/shm/specula-e2e-case-012/<tag> (removed afterwards); log in spec/output/<tag>.log
set -uo pipefail
spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mod="$1"; cfg="$2"; tag="$3"; minutes="$4"; workers="$5"; shift 5
lib=/work/lib
meta="/dev/shm/specula-e2e-case-012/$tag"
log="$spec_dir/output/$tag.log"
rm -rf "$meta"; mkdir -p "$(dirname "$meta")"
start=$(date +%s)
( cd "$spec_dir" && timeout --signal=TERM --kill-after=30 "${minutes}m" \
    java -XX:+UseParallelGC -Xmx${XMX:-12g} -Dtlc2.TLC.stopAfter=$((minutes*60 - 20)) \
    -cp "$lib/tla2tools.jar:$lib/CommunityModules-deps.jar" tlc2.TLC \
    -config "$cfg" -metadir "$meta" -workers "$workers" -cleanup "$@" "$mod.tla" ) > "$log" 2>&1
rc=$?
end=$(date +%s)
rm -rf "$meta"
echo "CMD: $mod.tla -config $cfg -workers $workers $* (outer timeout ${minutes}m)" >> "$log"
echo "EXIT: rc=$rc elapsed=$((end-start))s" >> "$log"
res=$(grep -E "Model checking completed|Invariant .* is violated|Temporal properties were violated|Action property .* violated|Error:" "$log" | head -1)
stats=$(grep -E "states generated" "$log" | tail -1)
depth=$(grep -E "depth of the complete state graph|The depth" "$log" | tail -1)
echo "$tag | rc=$rc | $((end-start))s | $res | $stats | $depth"
