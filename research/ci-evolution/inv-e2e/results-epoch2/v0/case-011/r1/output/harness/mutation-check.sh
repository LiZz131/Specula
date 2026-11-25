#!/usr/bin/env bash
# Negative control: every single-field mutant of a fresh trace must FAIL replay.
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mdir="$suite_root/traces/mutants"
rm -rf "$mdir"; python3 -I "$suite_root/harness/tools/make_mutants.py" "$suite_root/traces" "$mdir" >/dev/null
run_state="/dev/shm/specula-e2e-case-011/mutants-$$"; mkdir -p "$run_state"
trap 'rm -rf "$run_state"' EXIT
cd "$suite_root/spec"; mkdir -p output/mutants
ok=0; bad=0
for f in "$mdir"/*.ndjson; do
  id=$(basename "$f" .ndjson); log="output/mutants/$id.log"
  timeout 5m env SPECULA_TRACE="$f" java -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar \
     tlc2.TLC -workers 1 -cleanup -metadir "$run_state/$id" -config Trace.cfg Trace > "$log" 2>&1
  rm -rf "$run_state/$id"
  if grep -q 'Model checking completed. No error has been found.' "$log"; then echo "UNDETECTED $id"; bad=$((bad+1));
  elif grep -qE 'Temporal properties were violated|is violated|Error:' "$log"; then echo "REJECTED $id"; ok=$((ok+1));
  else echo "UNKNOWN $id"; bad=$((bad+1)); fi
done
echo "mutants rejected=$ok undetected_or_unknown=$bad"
