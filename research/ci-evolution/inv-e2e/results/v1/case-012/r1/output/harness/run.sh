#!/usr/bin/env bash
# One-command trace collection for the UPDATED revision (rebased V0 harness).
# Toolchain: the tree pins nightly-2022-03-30 (rust-toolchain), which is not
# installed and cannot be installed (read-only RUSTUP_HOME); the V0 harness used
# `cargo +nightly`.  This run uses `cargo +stable` (see INSTRUMENTATION.md).
set -euo pipefail

out_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_tree="${SPECULA_WORK_SOURCE:-$out_dir/work/instrumented}"
trace_dir="$out_dir/traces"
log_dir="$out_dir/spec/output"
toolchain="${SPECULA_TOOLCHAIN:-+stable}"

bash "$out_dir/harness/apply.sh"
mkdir -p "$trace_dir" "$log_dir"

(cd "$work_tree" && timeout 900s cargo "$toolchain" test -p openraft --lib --no-run) \
    >"$log_dir/harness-build.log" 2>&1

run_case() {
    local name="$1"
    local test_name="$2"
    local event_filter="${3:-}"
    local trace_file="$trace_dir/$name.ndjson"
    local raw_file="$trace_dir/$name.raw.ndjson"
    local log_file="$log_dir/harness-$name.log"
    rm -f "$trace_file" "$raw_file"
    (
        cd "$work_tree"
        timeout 300s env SPECULA_TRACE=1 SPECULA_TRACE_FILE="$raw_file" \
            cargo "$toolchain" test -p openraft --lib "$test_name" -- --exact --nocapture
    ) >"$log_file" 2>&1
    timeout 30s python3 "$out_dir/harness/preprocess_trace.py" \
        "$raw_file" "$trace_file" "$event_filter" >>"$log_file"
    rm -f "$raw_file"
    test -s "$trace_file"
    echo "$name: $(wc -l < "$trace_file") events"
}

# --- prior V0 regression scenarios (rerun on the updated revision) ---
run_case election 'engine::specula_trace_test::specula_trace_election_single'
run_case leader_append 'engine::leader_append_entries_test::test_leader_append_entries_normal'
# V0 used test_leader_append_entries_with_membership, which the update replaced
# by the fast_commit_* membership tests; this is the same batch shape (blank,
# membership m34, blank).
run_case leader_membership_append 'engine::leader_append_entries_test::test_leader_append_entries_fast_commit_upto_membership_entry'
run_case follower_commit 'engine::follower_commit_entries_test::test_follower_commit_entries_gt_last_entry'
run_case membership_update 'engine::update_committed_membership_test::test_update_committed_membership_at_index_3'
run_case progress 'progress::t::vec_progress_update'
run_case quorum 'membership::effective_membership_test::test_effective_membership_majority'
run_case replication_state 'core::replication_state_test::test_is_line_rate'
# V0 greatest_majority (membership_test::test_membership_greatest_majority_value)
# is superseded: Membership::greatest_majority_value and its test were deleted
# by the update.

# --- update-focused scenarios (derived from the diff) ---
run_case leader_fast_commit 'engine::leader_append_entries_test::test_leader_append_entries_fast_commit'
run_case leader_membership_no_voter_change 'engine::leader_append_entries_test::test_leader_append_entries_fast_commit_membership_no_voter_change'
run_case leader_membership_to_1 'engine::leader_append_entries_test::test_leader_append_entries_fast_commit_if_membership_voter_change_to_1'
run_case update_progress 'engine::update_progress_test::test_update_progress_update_leader_progress'
run_case update_effective_membership_leader 'engine::update_effective_membership_test::test_update_effective_membership_for_leader'
run_case progress_upgrade 'progress::t::vec_progress_upgrade_quorum_set'
run_case u1_joint_commit_order 'engine::specula_update_test::specula_update_joint_commit_order'
run_case u2_uniform_commit 'engine::specula_update_test::specula_update_uniform_commit'
run_case u3_follower_no_advance 'engine::specula_update_test::specula_follower_commit_no_advance'

for trace_file in "$trace_dir"/*.ndjson; do
    while IFS= read -r line; do
        printf '%s\n' "$line" | python3 -m json.tool >/dev/null
    done < "$trace_file"
done
echo "all traces are valid NDJSON"
