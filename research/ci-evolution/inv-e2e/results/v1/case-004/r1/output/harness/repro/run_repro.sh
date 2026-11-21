#!/usr/bin/env bash
# Reproduction for MC-1. usage: run_repro.sh <source-tree> <new|old> <log>
#   new: copies t98_specula_repro_transfer_leader_to_learner.rs (needs Raft::transfer_leader)
#   old: copies t98_specula_control_old_elect_learner.rs (baseline control)
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; tree="$1"; mode="$2"; log="$3"
out_root="$(cd "$here/../.." && pwd)"
export CARGO_TARGET_DIR="$out_root/build/cargo-target-repro-$mode"   # always under the output tree
f=$([ "$mode" = new ] && echo t98_specula_repro_transfer_leader_to_learner.rs || echo t98_specula_control_old_elect_learner.rs)
mod=${f%.rs}
cp "$here/$f" "$tree/tests/tests/client_api/$f"
grep -q "^mod $mod;" "$tree/tests/tests/client_api/main.rs" || sed -i "0,/^mod t/s//mod $mod;\nmod t/" "$tree/tests/tests/client_api/main.rs"
cd "$tree"
[ -f Cargo.lock ] || cp "$here/../Cargo.lock" Cargo.lock
{ echo "# tree: $tree  rev: $(git rev-parse HEAD) ($(git log -1 --format=%s))  mode: $mode  CARGO_TARGET_DIR=$CARGO_TARGET_DIR"; echo "# cmd: timeout 15m cargo +stable test -p tests --test client_api $mod -- --test-threads=1 --nocapture"; } > "$log"
timeout 15m cargo +stable test -p tests --test client_api "$mod" -- --test-threads=1 --nocapture >> "$log" 2>&1
rc=$?; echo "# exit: $rc" >> "$log"; exit $rc
