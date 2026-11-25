#!/usr/bin/env bash
# Usage: run-tlc.sh <Module.tla> <cfg> <tag> <bfs|sim> <minutes> [workers] [simDepth]
# Planned exploration limit via -Dtlc2.TLC.stopAfter (graceful), plus an
# outer timeout.  TLC state under /dev/shm/specula-e2e-case-002, removed after.
set -uo pipefail
spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mod="$1"; cfg="$2"; tag="$3"; mode="$4"; mins="$5"; workers="${6:-8}"; depth="${7:-120}"
log="$spec_dir/output/mc-$tag.log"
meta="/dev/shm/specula-e2e-case-002/mc-$tag-$$"
mkdir -p "$meta" "$spec_dir/output"
cd "$spec_dir"
secs=$((mins*60))
args=(-config "$cfg" -metadir "$meta" -workers "$workers" -dumpTrace json "output/mc-$tag.cex.json" -cleanup)
[[ "$mode" == sim ]] && args+=(-simulate num=999999999 -depth "$depth")
cmd=(java -XX:+UseParallelGC -Xmx24g -Dtlc2.TLC.stopAfter=$secs
     -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC "${args[@]}" "$mod")
echo "# command: timeout $((secs+600))s ${cmd[*]}" > "$log"
echo "# started: $(date -u +%FT%TZ)" >> "$log"
timeout $((secs+600))s "${cmd[@]}" >> "$log" 2>&1
rc=$?
echo "# exit: $rc finished: $(date -u +%FT%TZ)" >> "$log"
rm -rf "$meta"
summary=$(grep -E "states generated|Model checking completed|violated|Error:|depth of the complete|states left on queue|traces generated|The number of states generated" "$log" | head -6 | tr '\n' ' ')
echo "[$tag] rc=$rc $summary"
exit 0
