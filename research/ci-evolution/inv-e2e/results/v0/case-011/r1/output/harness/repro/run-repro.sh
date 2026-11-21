#!/usr/bin/env bash
# Install and run the Specula reproduction tests (MC-1, MC-2) against a writable
# source tree (default: the instrumented working copy of the `update` revision).
# The tests assert the expected, non-disruptive behavior: a FAILED test means
# the defect reproduced. usage: run-repro.sh [MC-1|MC-2|all]
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src="${SPECULA_REPRO_SOURCE:-$suite_root/work-source}"
out="$suite_root/spec/output"
export CARGO_HOME="${CARGO_HOME:-/work/.cache/cargo}"
# One target dir per source tree: copies of the same workspace at different
# paths otherwise share path-independent artifacts and mtime fingerprints.
export CARGO_TARGET_DIR="${SPECULA_REPRO_TARGET:-/work/.cache/cargo-target-$(basename "$src")}"
export RUSTUP_TOOLCHAIN="${SPECULA_RUST_TOOLCHAIN:-stable}"
label="${SPECULA_REPRO_LABEL:-update}"
which="${1:-all}"
rd="$suite_root/harness/repro"

install_engine() { cp "$rd/$1.rs" "$src/openraft/src/engine/tests/"
  grep -q "mod $1;" "$src/openraft/src/engine/mod.rs" || \
    sed -i "s/^    mod startup_test;\$/    mod startup_test;\n    mod $1;/" "$src/openraft/src/engine/mod.rs"; }
install_it() { cp "$rd/$1.rs" "$src/tests/tests/elect/"
  grep -q "mod $1;" "$src/tests/tests/elect/main.rs" || echo "mod $1;" >> "$src/tests/tests/elect/main.rs"; }

run_case() { # id engine_mod engine_filter it_mod
  local id="$1" emod="$2" efilter="$3" imod="$4"
  install_engine "$emod"; install_it "$imod"
  cd "$src"
  local elog="$out/repro-$id-engine-$label.log" rlog="$out/repro-$id-runtime-$label.log"
  echo "# source: $src HEAD=$(git rev-parse HEAD 2>/dev/null) toolchain=$RUSTUP_TOOLCHAIN $(date -u +%FT%TZ)" > "$elog"
  echo "# command: cargo test -p openraft --lib $efilter -- --nocapture" >> "$elog"
  timeout 20m cargo test -p openraft --lib "$efilter" -- --nocapture >> "$elog" 2>&1
  echo "# exit=$?" >> "$elog"
  echo "# source: $src HEAD=$(git rev-parse HEAD 2>/dev/null) toolchain=$RUSTUP_TOOLCHAIN $(date -u +%FT%TZ)" > "$rlog"
  echo "# command: cargo test -p tests --test elect $imod -- --nocapture (x3)" >> "$rlog"
  for k in 1 2 3; do
    echo "## run $k" >> "$rlog"
    RUST_LOG=off timeout 10m cargo test -p tests --test elect "$imod" -- --nocapture >> "$rlog" 2>&1
    echo "# exit=$?" >> "$rlog"
  done
  grep -E "^test |panicked at|assertion|left:|right:|# exit|after |delivered" "$elog" "$rlog"
}
[ "$which" = all -o "$which" = MC-1 ] && run_case MC-1 specula_repro_stale_pre_vote_test specula_repro_stale_pre_vote t90_specula_stale_pre_vote
[ "$which" = all -o "$which" = MC-2 ] && run_case MC-2 specula_repro_removed_leader_pre_vote_test specula_repro_removed_leader_pre_vote t91_specula_removed_leader_pre_vote
exit 0
