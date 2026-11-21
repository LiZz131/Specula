#!/usr/bin/env bash
# Bounded TLC run. usage: run_tlc.sh <Module.tla> <cfg> <label> <minutes> [extra TLC args...]
# - TLC state dir: /dev/shm/specula-e2e-case-004/<label>-<pid> (removed afterwards)
# - log: spec/output/mc-<label>.log ; counterexample TE specs: spec/output/ttrace-<label>/
# - graceful stop after <minutes> (tlc2.TLC.stopAfter) plus an outer timeout (+10 min).
set -uo pipefail
spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mod="$1"; cfg="$2"; label="$3"; mins="$4"; shift 4
workers="${TLC_WORKERS:-8}"
heap="${TLC_HEAP:-12g}"
meta="/dev/shm/specula-e2e-case-004/$label-$$"
log="$spec_dir/output/mc-$label.log"
te="$spec_dir/output/ttrace-$label"
mkdir -p "$spec_dir/output" /dev/shm/specula-e2e-case-004 "$te"
echo "# cmd: run_tlc.sh $mod $cfg $label $mins $* (workers=$workers heap=$heap)" > "$log"
echo "# started: $(date -u +%FT%TZ)" >> "$log"
( cd "$spec_dir" && timeout $((mins + 10))m java -Xmx"$heap" -XX:+UseParallelGC \
    -Dtlc2.TLC.stopAfter=$((mins * 60)) \
    -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC \
    -workers "$workers" -metadir "$meta" -teSpecOutDir "$te" -config "$cfg" "$@" "$mod" ) >> "$log" 2>&1
rc=$?
rm -rf "$meta"
echo "# finished: $(date -u +%FT%TZ) rc=$rc" >> "$log"
[ -d "$te" ] && [ -z "$(ls -A "$te")" ] && rmdir "$te"
grep -E "Invariant .* is violated|Temporal properties were violated|Action property .* violated|Model checking completed|states generated|depth of the complete|Error:|stopAfter|Exit" "$log" | grep -v "^#" | tail -6
exit $rc
