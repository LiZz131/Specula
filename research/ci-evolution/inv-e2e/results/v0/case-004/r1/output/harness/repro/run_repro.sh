#!/usr/bin/env bash
# Reproduce MC-1 on an UNINSTRUMENTED copy of the updated source (artifact commit `update`).
# Usage: run_repro.sh [source_tree]   (default: ../../artifact).  Writes ../../spec/output/repro-MC-1.log
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
suite="$(cd "$here/../.." && pwd)"
src="${1:-$suite/artifact}"
tree="$suite/build/repro-source"
log="$suite/spec/output/repro-MC-1.log"
rm -rf "$tree"; cp -a "$src" "$tree"
{
  echo "source: $(git -C "$tree" rev-parse HEAD 2>/dev/null) $(git -C "$tree" log -1 --format=%s 2>/dev/null)"
  echo "instrumentation: none (test file only)"
} > "$log"
cp "$here/test_bugMC-1_transfer_leader_to_learner.rs" "$tree/tests/tests/client_api/t90_repro_mc1_transfer_to_learner.rs"
sed -i 's/^mod t14_transfer_leader;$/mod t14_transfer_leader;\nmod t90_repro_mc1_transfer_to_learner;/' "$tree/tests/tests/client_api/main.rs"
cd "$tree"
timeout 20m env CARGO_TARGET_DIR="$suite/build/cargo-target-repro-update" cargo +stable test -p tests --test client_api \
  t90_repro_mc1_transfer_to_learner -- --nocapture --test-threads=1 >> "$log" 2>&1
rc=$?
echo "EXIT rc=$rc" >> "$log"
grep -E "REPRO-MC-1|panicked at|target not in quorum set|test result" "$log"
exit $rc
