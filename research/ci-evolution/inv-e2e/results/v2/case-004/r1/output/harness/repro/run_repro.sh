#!/usr/bin/env bash
# Reproduction / controls for MC-1. Requires the instrumentation patch (harness/apply.sh).
# usage: run_repro.sh [work_tree]   (default ../../artifact). Output: spec/output/repro-*.log
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
tree="${1:-$root/artifact}"
f="$tree/tests/tests/client_api/t99_specula_transfer.rs"
cp "$f" "$f.specula-bak"
{ echo; echo "// ---- appended by harness/repro/run_repro.sh ----"; echo "mod specula_repro {"; sed 's|^use crate::fixtures|use crate::fixtures|' "$here/t99_specula_repro.rs"; echo "}"; } >> "$f"
for t in specula_repro_transfer_to_learner_no_panic specula_control_trigger_elect_on_learner; do
  ( cd "$tree" && timeout 15m cargo +stable test -p tests --test client_api "t99_specula_transfer::specula_repro::$t" -- --exact --nocapture --test-threads=1 ) > "$root/spec/output/repro-$t.log" 2>&1
  echo "$t rc=$?"; grep -E "SPECULA_(REPRO|CONTROL)|panicked at|test result|Error:" "$root/spec/output/repro-$t.log" | head -6
done
mv "$f.specula-bak" "$f"
