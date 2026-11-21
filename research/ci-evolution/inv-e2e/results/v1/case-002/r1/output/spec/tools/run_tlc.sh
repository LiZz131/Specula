#!/usr/bin/env bash
# Usage: run_tlc.sh <module> <cfg> <tag> <minutes> <workers> [extra TLC args...]   (run from spec/)
set -uo pipefail
mod="$1"; cfg="$2"; tag="$3"; mins="$4"; workers="$5"; shift 5
meta="/dev/shm/specula-e2e-case-002/mc-$tag-$$"
log="output/mc-$tag.log"
mkdir -p "$meta"
outer=$(( mins * 60 + 300 ))
cmd=(timeout "${outer}s" java -Xmx${HEAP:-24g} -XX:+UseParallelGC -Dtlc2.TLC.stopAfter=$(( mins * 60 ))
     -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar
     tlc2.TLC -cleanup -workers "$workers" -config "$cfg" -metadir "$meta" "$@" "$mod.tla")
{ echo "# cwd: $(pwd)"; echo "# cmd: ${cmd[*]}"; echo "# started: $(date -u +%FT%TZ)"; } > "$log"
"${cmd[@]}" >> "$log" 2>&1
rc=$?
{ echo "# exit: $rc"; echo "# finished: $(date -u +%FT%TZ)"; } >> "$log"
rm -rf "$meta"
mv -f ${mod}_TTrace_*.tla ${mod}_TTrace_*.bin output/ 2>/dev/null
echo "$tag rc=$rc :: $(grep -E 'is violated|No error has been found|Error:|states generated|depth of the complete|exceeded|TLC is stopping' "$log" | tail -4 | tr '\n' ' ')"
