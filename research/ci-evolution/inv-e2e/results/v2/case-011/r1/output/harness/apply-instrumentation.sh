#!/usr/bin/env bash
# Apply the test-only Specula instrumentation to the updated source tree.
# Copy-and-patch: copies harness/src/specula_trace_test.rs into the engine test
# module directory and registers it in openraft/src/engine/mod.rs.
# Default target: the artifact tree of this run (override SPECULA_WORK_SOURCE).
set -euo pipefail

harness_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
suite_root="$(cd "$harness_dir/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$suite_root/artifact}"
mod_file="$work_source/openraft/src/engine/mod.rs"

cp "$harness_dir/src/specula_trace_test.rs" "$work_source/openraft/src/engine/tests/specula_trace_test.rs"
if ! grep -q 'mod specula_trace_test;' "$mod_file"; then
    # Register next to the existing `mod startup_test;` declaration (symbol anchor, not a line number).
    sed -i 's/^\(    mod startup_test;\)$/\1\n    mod specula_trace_test;/' "$mod_file"
fi
grep -q 'mod specula_trace_test;' "$mod_file"

# End-to-end RaftCore reproduction for finding MC-1 (integration test target `elect`).
elect_main="$work_source/tests/tests/elect/main.rs"
cp "$harness_dir/src/t90_specula_repro_stale_prevote_leader.rs" "$work_source/tests/tests/elect/t90_specula_repro_stale_prevote_leader.rs"
if ! grep -q 'mod t90_specula_repro_stale_prevote_leader;' "$elect_main"; then
    echo 'mod t90_specula_repro_stale_prevote_leader;' >> "$elect_main"
fi
# End-to-end RaftCore reproduction for finding MC-2 (stale Pre-Vote round).
cp "$harness_dir/src/t91_specula_repro_prevote_stale_round_panic.rs" "$work_source/tests/tests/elect/t91_specula_repro_prevote_stale_round_panic.rs"
if ! grep -q 'mod t91_specula_repro_prevote_stale_round_panic;' "$elect_main"; then
    echo 'mod t91_specula_repro_prevote_stale_round_panic;' >> "$elect_main"
fi
# Test-support store only (stores/memstore): optional save_vote delay used by the reproduction.
if ! grep -q 'DelaySaveVote' "$work_source/stores/memstore/src/lib.rs"; then
    git -C "$work_source" apply "$harness_dir/patches/memstore-delay-save-vote.patch"
fi
echo "Applied test-only instrumentation to $work_source"
