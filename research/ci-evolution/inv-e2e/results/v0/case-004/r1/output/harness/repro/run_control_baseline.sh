#!/usr/bin/env bash
# Old-revision control for MC-1 on the baseline commit (no transfer_leader API exists there).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
suite="$(cd "$here/../.." && pwd)"
tree="$suite/build/control-baseline-source"
log="$suite/spec/output/control-MC-1-baseline.log"
rm -rf "$tree"; cp -a "$suite/artifact" "$tree"
git -C "$tree" checkout -q baseline 2>/dev/null || git -C "$tree" checkout -q HEAD~1
{ echo "source: $(git -C "$tree" rev-parse HEAD) $(git -C "$tree" log -1 --format=%s)"; \
  echo "transfer_leader present: $(grep -c 'pub async fn transfer_leader' "$tree/openraft/src/raft/mod.rs")"; } > "$log"
cp "$here/control_baseline_learner_elect.rs" "$tree/tests/tests/client_api/t91_control_mc1.rs"
sed -i 's/^mod t13_trigger_snapshot;$/mod t13_trigger_snapshot;\nmod t91_control_mc1;/' "$tree/tests/tests/client_api/main.rs"
cd "$tree"
timeout 20m env CARGO_TARGET_DIR="$suite/build/cargo-target-control-baseline" cargo +stable test -p tests --test client_api \
  t91_control_mc1 -- --nocapture --test-threads=1 >> "$log" 2>&1
rc=$?; echo "EXIT rc=$rc" >> "$log"
grep -E "^source|transfer_leader present|CONTROL-MC-1|panicked at|test result" "$log"; exit $rc
