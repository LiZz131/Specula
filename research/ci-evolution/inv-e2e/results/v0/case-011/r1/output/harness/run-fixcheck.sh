#!/usr/bin/env bash
# Model-level sanity control: run cfgs against spec/fixcheck/ (the reference
# with the candidate MC-1 fix applied to HandleVoteResponse). Not the reference.
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
secs="$1"; shift
fixdir="${SPECULA_FIXDIR:-fixcheck}"
for cfg in "$@"; do
  label="${fixdir}-${cfg%.cfg}"
  state="/dev/shm/specula-e2e-case-011/$label-$$"
  log="$suite_root/spec/output/mc-$label.log"
  mkdir -p "$state"
  echo "# command: (cd spec/$fixdir) java -Xmx20g -Dtlc2.TLC.stopAfter=$secs tlc2.TLC -workers 8 -metadir $state -config $cfg Update" > "$log"
  (cd "$suite_root/spec/$fixdir" && timeout $((secs+600)) java -Xmx20g -XX:+UseParallelGC -Dtlc2.TLC.stopAfter="$secs" \
     -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -workers 8 -metadir "$state" -config "$cfg" Update >> "$log" 2>&1)
  echo "# exit: $? $(date -u +%FT%TZ)" >> "$log"
  rm -rf "$state" "$suite_root"/spec/$fixdir/*_TTrace_*.tla
  echo "$(date -u +%FT%TZ) | $label | $fixdir/$cfg | $(grep -m1 -E 'is violated' "$log" || echo 'no violation') | $(grep -E 'states generated, .* distinct' "$log" | tail -1) | $(grep -E 'depth of the complete' "$log" | tail -1)" >> "$suite_root/spec/output/campaign-summary.txt"
done
