#!/usr/bin/env bash
# Bounded TLC run. Usage: run_tlc.sh <Module> <cfg> <tag> <bfs|sim> <minutes> [workers] [depth]
# States: /dev/shm/specula-e2e-case-012/<tag> (removed after the run); log: spec/output/mc-<tag>.log
set -uo pipefail
out_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$out_dir/spec"
mod="$1"; cfg="$2"; tag="$3"; mode="$4"; mins="$5"; workers="${6:-8}"; depth="${7:-100}"
meta="/dev/shm/specula-e2e-case-012/$tag"
log="$spec_dir/output/mc-$tag.log"
cp="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
rm -rf "$meta"; mkdir -p "$meta"
extra=()
if [ "$mode" = "sim" ]; then extra=(-simulate num=999999999 -depth "$depth"); fi
secs=$((mins * 60))
{
  echo "# cmd: java tlc2.TLC -config $cfg -metadir $meta -workers $workers ${extra[*]} $mod.tla (outer timeout ${secs}s+300s)"
  echo "# start: $(date -Is)"
} > "$log"
( cd "$spec_dir" && timeout --signal=TERM $((secs + 300)) java -XX:+UseParallelGC -Xmx${TLC_XMX:-16g} \
    -Dtlc2.TLC.stopAfter=$secs -cp "$cp" tlc2.TLC -config "$cfg" -metadir "$meta" \
    -workers "$workers" -deadlock "${extra[@]}" "$mod.tla" ) >> "$log" 2>&1
rc=$?
echo "# exit: $rc end: $(date -Is)" >> "$log"
rm -rf "$meta"
echo "$tag rc=$rc $(grep -E 'distinct states found|states generated' "$log" | tail -1) $(grep -oE 'Invariant [A-Za-z0-9_]+ is violated|Temporal properties were violated|Action property [A-Za-z0-9_]+ is violated|Model checking completed. No error has been found|Stopping TLC|depth of the complete state graph search is [0-9]+' "$log" | sort -u | tr '\n' ';')"
