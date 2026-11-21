#!/usr/bin/env bash
# Usage: run_tlc.sh <Module.tla> <cfg> <label> <bfs|sim> <minutes> [extra TLC args...]
# Bounded TLC run: outer timeout = minutes (+2m grace); states under
# /dev/shm/specula-e2e-case-003/, removed afterwards; log in spec/output/mc-v1-<label>.log.
set -uo pipefail
spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mod="$1"; cfg="$2"; label="$3"; mode="$4"; mins="$5"; shift 5
lib=/work/lib
meta="/dev/shm/specula-e2e-case-003/mc-$label-$$"
log="$spec_dir/output/mc-v1-$label.log"
workers="${TLC_WORKERS:-8}"
heap="${TLC_HEAP:-8g}"
args=(-config "$cfg" -metadir "$meta" -workers "$workers" -cleanup)
if [ "$mode" = sim ]; then args+=(-simulate "num=999999999" -depth "${SIM_DEPTH:-100}"); fi
mkdir -p "$(dirname "$meta")" "$spec_dir/output"
{
  echo "cmd: cd $spec_dir && timeout --signal=TERM $((mins+2))m java -XX:+UseParallelGC -Xmx$heap -Dtlc2.TLC.stopAfter=$((mins*60)) -cp $lib/tla2tools.jar:$lib/CommunityModules-deps.jar tlc2.TLC ${args[*]} $* $mod"
  echo "spec sha256: $(cd "$spec_dir" && sha256sum base.tla MC.tla Update.tla "$cfg" | awk '{printf "%s=%s ", $2, substr($1,1,16)}')"
  echo "start: $(date -Is)"
} > "$log"
(cd "$spec_dir" && timeout --signal=TERM $((mins+2))m java -XX:+UseParallelGC -Xmx"$heap" \
   -Dtlc2.TLC.stopAfter=$((mins*60)) \
   -cp "$lib/tla2tools.jar:$lib/CommunityModules-deps.jar" tlc2.TLC "${args[@]}" "$@" "$mod") >> "$log" 2>&1
rc=$?
echo "end: $(date -Is) tlc exit=$rc" >> "$log"
rm -rf "$meta"
summary=$(grep -E "Model checking completed|Invariant .* is violated|Temporal properties were violated|Action property .* is violated|Error: Deadlock|states generated|depth of the complete|stopAfter|The number of states generated|Progress\(" "$log" | tail -4 | tr '\n' ' ')
echo "[$label] exit=$rc :: $summary"
exit $rc
