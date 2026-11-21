#!/usr/bin/env bash
# Revert the test-only instrumentation from the work tree.
set -euo pipefail
harness_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
suite_root="$(cd "$harness_dir/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$suite_root/artifact}"
git -C "$work_source" checkout -- openraft/src/engine/mod.rs
rm -f "$work_source/openraft/src/engine/tests/specula_trace_test.rs"
git -C "$work_source" checkout -- tests/tests/elect/main.rs stores/memstore/src/lib.rs
rm -f "$work_source/tests/tests/elect/t90_specula_repro_stale_prevote_leader.rs" "$work_source/tests/tests/elect/t91_specula_repro_prevote_stale_round_panic.rs"
echo "Removed instrumentation from $work_source"
