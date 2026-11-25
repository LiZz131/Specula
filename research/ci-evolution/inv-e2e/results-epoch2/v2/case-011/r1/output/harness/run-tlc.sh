#!/usr/bin/env bash
# Usage: run-tlc.sh <module> <cfg> <label> <minutes> <workers> [extra TLC flags...]
# Bounded TLC run: outer `timeout <minutes>m` (budget), states in
# /dev/shm/specula-e2e-case-011/mc-<label> (removed afterwards), log in
# spec/output/mc-<label>.log. A run stopped by its budget is LIMITED_COVERAGE.
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
module="$1"; cfg="$2"; label="$3"; minutes="$4"; workers="$5"; shift 5
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
meta="/dev/shm/specula-e2e-case-011/mc-$label"
log="$spec_dir/output/mc-$label.log"
heap="${SPECULA_TLC_HEAP:-20g}"
mkdir -p "$(dirname "$meta")"; rm -rf "$meta"
cmd=(timeout --signal=TERM --kill-after=60s "${minutes}m" java -Xmx"$heap" -XX:+UseParallelGC
     -Dtlc2.TLC.stopAfter=$((minutes*60 - 30)) -cp "$classpath" tlc2.TLC
     -workers "$workers" -metadir "$meta" -noGenerateSpecTE
     -dumpTrace json "$spec_dir/output/mc-$label.cex.json" -config "$cfg" "$@" "$module")
cd "$spec_dir"
{ echo "COMMAND: cd $spec_dir && ${cmd[*]}"; echo "START: $(date -Is)"; } > "$log"
"${cmd[@]}" >> "$log" 2>&1
rc=$?
{ echo "EXIT: $rc"; echo "END: $(date -Is)"; } >> "$log"
rm -rf "$meta"
echo "$label exit=$rc $(grep -E 'Model checking completed|is violated|Error:|states generated' "$log" | tail -2 | tr '\n' ' ')"
