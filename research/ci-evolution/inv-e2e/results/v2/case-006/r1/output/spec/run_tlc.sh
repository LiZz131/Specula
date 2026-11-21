#!/usr/bin/env bash
# Bounded TLC runner: run_tlc.sh <name> <Module.tla> <cfg> <bfs|sim> <minutes> <workers> [extra TLC args...]
# States under /dev/shm/specula-e2e-case-006/<name> (removed afterwards); log in spec/output/mc-<name>.log;
# counterexamples (if any) in spec/output/cex/<name>.{json,tla}.
set -uo pipefail
SPEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
name="$1"; mod="$2"; cfg="$3"; mode="$4"; mins="$5"; workers="$6"; shift 6
TLA_CP="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
STATE="/dev/shm/specula-e2e-case-006/$name"
LOG="$SPEC_DIR/output/mc-$name.log"
mkdir -p "$STATE" "$SPEC_DIR/output/cex"
cd "$SPEC_DIR"
secs=$((mins * 60))
modeargs=()
if [ "$mode" = sim ]; then modeargs=(-simulate -depth 100); fi
{
  echo "# command: java -Xmx16g -Dtlc2.TLC.stopAfter=$secs tlc2.TLC ${modeargs[*]} -workers $workers -metadir $STATE -config $cfg $mod $*"
  echo "# started: $(date -u +%FT%TZ) budget=${mins}m outer-timeout=$((mins + 5))m"
} > "$LOG"
timeout $(( (mins + 5) * 60 )) java -Xmx16g -XX:+UseParallelGC -Dtlc2.TLC.stopAfter=$secs \
    -cp "$TLA_CP" tlc2.TLC "${modeargs[@]}" -workers "$workers" -metadir "$STATE" \
    -dumpTrace json "output/cex/$name.json" -dumpTrace tla "output/cex/$name.tla" -teSpecOutDir output/te \
    -config "$cfg" "$mod" "$@" >> "$LOG" 2>&1
rc=$?
echo "# finished: $(date -u +%FT%TZ) rc=$rc" >> "$LOG"
find "$STATE" -depth -delete 2>/dev/null
rmdir /dev/shm/specula-e2e-case-006 2>/dev/null || true
summary=$(grep -E "^Error: |violated|Model checking completed|states generated|depth of the complete|stopAfter|Stopping|The number of states generated" "$LOG" | tail -4 | tr '\n' ' ')
echo "$name rc=$rc :: $summary"
