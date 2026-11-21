#!/usr/bin/env bash
# Specula harness (V0 Engine harness rebased onto the update commit + update-focused RaftCore
# probes). One command: apply instrumentation, build, run scenarios, collect fresh traces.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_root="$(cd "$here/.." && pwd)"
work_tree="${SPECULA_WORK_TREE:-$output_root/artifact}"
trace_dir="$output_root/traces"
log_dir="$output_root/spec/output"
unit_log="$log_dir/harness-unit.log"
core_log="$log_dir/harness-core.log"
toolchain="${SPECULA_TOOLCHAIN:-+stable}"

mkdir -p "$trace_dir" "$log_dir"
: >"$unit_log"
: >"$core_log"

"$here/apply.sh" | tee -a "$unit_log"

echo "source: $(git -C "$work_tree" rev-parse HEAD) ($(git -C "$work_tree" log -1 --format=%s))" | tee -a "$unit_log" "$core_log"
cargo "$toolchain" --version | tee -a "$unit_log" "$core_log"

# ---- V0 Engine-boundary scenarios (rebased; unchanged scenario logic) -------------------------
run_unit() {
    local test_name="$1" trace_name="$2"
    local trace_file="$trace_dir/$trace_name.ndjson"
    rm -f "$trace_file"
    (
        cd "$work_tree"
        timeout 15m env SPECULA_TRACE_FILE="$trace_file" \
            cargo "$toolchain" test -p openraft --lib \
                "engine::specula_trace_tests::$test_name" -- \
                --exact --nocapture --test-threads=1
    ) 2>&1 | tee -a "$unit_log"
    test -s "$trace_file"
}

run_unit specula_trace_election election
run_unit specula_trace_vote_request vote-request
run_unit specula_trace_follower_append follower-append
run_unit specula_trace_learner_membership learner-membership
run_unit specula_trace_joint_membership joint-membership
run_unit specula_trace_uniform_membership uniform-membership
run_unit specula_trace_partial_replication partial-replication
run_unit specula_trace_restart restart

# ---- Update-focused RaftCore scenarios -----------------------------------------------------------
run_core() {
    local test_filter="$1" name="$2"
    local dir="$trace_dir/core-$name"
    rm -rf "$dir"
    mkdir -p "$dir"
    rm -f "$log_dir/obs-$name.jsonl"
    echo "=== core scenario $name ($test_filter)" | tee -a "$core_log"
    (
        cd "$work_tree"
        timeout 15m env RUST_BACKTRACE=1 SPECULA_CORE_TRACE_DIR="$dir" \
            SPECULA_OBS_FILE="$log_dir/obs-$name.jsonl" \
            cargo "$toolchain" test -p tests --test client_api "$test_filter" -- \
                --exact --nocapture --test-threads=1
    ) >>"$core_log" 2>&1
    grep -E "^test |test result" "$core_log" | tail -2
    ls "$dir"/*.ndjson >/dev/null
    for f in "$dir"/*.ndjson; do test -s "$f"; done
}

run_core t14_transfer_leader::transfer_leader t14-transfer-leader
run_core t99_specula_transfer::specula_transfer_all_nodes transfer-all-nodes
run_core t99_specula_transfer::specula_transfer_to_learner transfer-to-learner

n_unit=$(ls "$trace_dir"/*.ndjson | wc -l)
n_core=$(ls "$trace_dir"/core-*/*.ndjson | wc -l)
printf 'collected %s unit traces and %s RaftCore session traces\n' "$n_unit" "$n_core" | tee -a "$unit_log" "$core_log"
