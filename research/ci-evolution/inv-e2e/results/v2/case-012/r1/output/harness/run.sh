#!/usr/bin/env bash
# V1 harness: rebased V0 harness on the updated revision (artifact commit `update`).
# Toolchain: the V0 harness used `cargo +nightly`; only the stable toolchain is
# installed in this environment (rust-toolchain pins an uninstallable
# nightly-2022-03-30), so V1 uses `cargo +stable` (see INSTRUMENTATION.md).
set -euo pipefail

out_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_tree="${SPECULA_WORK_SOURCE:-$out_dir/work-source}"
trace_dir="$out_dir/traces"
raw_dir="$out_dir/traces/raw"
log_dir="$out_dir/spec/output"
toolchain="${SPECULA_CARGO_TOOLCHAIN:-+stable}"

bash "$out_dir/harness/apply.sh"
mkdir -p "$trace_dir" "$raw_dir" "$log_dir"

(cd "$work_tree" && timeout 900s cargo $toolchain test -p openraft --lib --no-run) \
    >"$log_dir/harness-build.log" 2>&1

run_case() {
    local name="$1"
    local test_name="$2"
    local event_filter="${3:-}"
    local trace_file="$trace_dir/$name.ndjson"
    local raw_file="$raw_dir/$name.raw.ndjson"
    local log_file="$log_dir/harness-$name.log"
    rm -f "$trace_file" "$raw_file"
    (
        cd "$work_tree"
        timeout 300s env SPECULA_TRACE=1 SPECULA_TRACE_FILE="$raw_file" \
            cargo $toolchain test -p openraft --lib "$test_name" -- --exact --nocapture
    ) >"$log_file" 2>&1
    timeout 30s python3 "$out_dir/harness/preprocess_trace.py" \
        "$raw_file" "$trace_file" "$event_filter"
    test -s "$trace_file"
    echo "$name: $(wc -l < "$trace_file") events (raw $(wc -l < "$raw_file"))"
}

# --- V0 regression scenarios rerun on the updated revision ---
run_case election 'engine::specula_trace_test::specula_trace_election_single'
run_case leader_append 'engine::leader_append_entries_test::test_leader_append_entries_normal'
# leader_membership_append: V0 test test_leader_append_entries_with_membership was
#   removed by the update (source drift); superseded by the leader_fast_commit_* cases.
run_case follower_commit 'engine::follower_commit_entries_test::test_follower_commit_entries_gt_last_entry'
run_case membership_update 'engine::update_committed_membership_test::test_update_committed_membership_at_index_3'
run_case progress 'progress::t::vec_progress_update'
run_case quorum 'membership::effective_membership_test::test_effective_membership_majority'
# greatest_majority: Membership::greatest_majority_value and its test were deleted by
#   the update; the joint commit calculation is now observed through UpdateProgress
#   (update_progress, leader_lifecycle).
run_case replication_state 'core::replication_state_test::test_is_line_rate'

# --- V1 update-focused scenarios (derived from the visible diff) ---
run_case leader_fast_commit 'engine::leader_append_entries_test::test_leader_append_entries_fast_commit'
run_case leader_fast_commit_upto_membership 'engine::leader_append_entries_test::test_leader_append_entries_fast_commit_upto_membership_entry'
run_case leader_fast_commit_membership_no_voter_change 'engine::leader_append_entries_test::test_leader_append_entries_fast_commit_membership_no_voter_change'
run_case leader_fast_commit_voter_change_to_1 'engine::leader_append_entries_test::test_leader_append_entries_fast_commit_if_membership_voter_change_to_1'
run_case update_progress 'engine::update_progress_test::test_update_progress_update_leader_progress'
run_case update_progress_no_leader 'engine::update_progress_test::test_update_progress_no_leader'
run_case update_effective_membership_leader 'engine::update_effective_membership_test::test_update_effective_membership_for_leader'
# index0 fixture: pre-state is inconsistent (empty log, no commit, committed membership
#   at index 1); validated with Trace_fixture.cfg (replay + TypeOK, no MembershipOrder).
run_case update_effective_membership_index0 'engine::update_effective_membership_test::test_update_effective_membership_at_index_0_is_allowed'
run_case leader_lifecycle 'engine::specula_trace_test::specula_trace_leader_lifecycle'
run_case follower_commit_no_advance 'engine::specula_trace_test::specula_trace_follower_commit_no_advance'
run_case update_effective_membership_to_learner 'engine::specula_trace_test::specula_trace_update_effective_membership_to_learner'

for trace_file in "$trace_dir"/*.ndjson; do
    while IFS= read -r line; do
        printf '%s\n' "$line" | python3 -m json.tool >/dev/null
    done < "$trace_file"
done
echo "all traces are valid NDJSON"
