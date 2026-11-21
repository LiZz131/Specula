#!/usr/bin/env bash
# One-command harness: apply instrumentation to an isolated copy of the updated
# source, run every selected scenario under an outer timeout, and regenerate one
# fresh NDJSON trace per scenario. Rebased from the V0 prior run.sh.
set -euo pipefail

out_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_tree="${SPECULA_WORK_SOURCE:-$out_dir/work-source}"
toolchain="${SPECULA_CARGO_TOOLCHAIN:-stable}"   # prior used +nightly; only stable is installed here
trace_dir="$out_dir/traces"
log_dir="$out_dir/spec/output"

bash "$out_dir/harness/apply.sh"
mkdir -p "$trace_dir" "$log_dir"

(cd "$work_tree" && timeout 1500s cargo +"$toolchain" test -p openraft --lib --no-run) \
    >"$log_dir/harness-build.log" 2>&1

run_case() {
    local name="$1"
    local test_name="$2"
    local event_filter="${3:-}"
    local trace_file="$trace_dir/$name.ndjson"
    local raw_file="$trace_dir/$name.raw.ndjson"
    local log_file="$log_dir/harness-$name.log"
    rm -f "$trace_file" "$raw_file" "$trace_dir/$name"-seg*.ndjson
    (
        cd "$work_tree"
        timeout 300s env SPECULA_TRACE=1 SPECULA_TRACE_FILE="$raw_file" \
            cargo +"$toolchain" test -p openraft --lib "$test_name" -- --exact --nocapture
    ) >"$log_file" 2>&1
    timeout 30s python3 -I "$out_dir/harness/preprocess_trace.py" \
        "$raw_file" "$trace_file" "$event_filter" >"$log_dir/preprocess-$name.log"
    rm -f "$raw_file"
    local produced=0
    for f in "$trace_file" "$trace_dir/$name"-seg*.ndjson; do
        if [ -s "$f" ]; then produced=1; echo "$(basename "$f"): $(wc -l < "$f") events"; fi
    done
    test "$produced" = 1
}

# --- Prior V0 regression scenarios (rerun on the updated implementation) ---
run_case election 'engine::specula_trace_test::specula_trace_election_single' Elect
run_case leader_append 'engine::leader_append_entries_test::test_leader_append_entries_normal' LeaderAppend
# V0 used test_leader_append_entries_with_membership, which the update removed;
# its closest successor appends a membership entry in the middle of a batch.
run_case leader_membership_append 'engine::leader_append_entries_test::test_leader_append_entries_fast_commit_upto_membership_entry' LeaderAppend
run_case follower_commit 'engine::follower_commit_entries_test::test_follower_commit_entries_gt_last_entry' FollowerCommit
run_case membership_update 'engine::update_committed_membership_test::test_update_committed_membership_at_index_3' UpdateCommittedMembership
run_case progress 'progress::t::vec_progress_update' ProgressUpdate
run_case quorum 'membership::effective_membership_test::test_effective_membership_majority' QuorumCheck
run_case replication_state 'core::replication_state_test::test_is_line_rate' ReplicationLagCheck
# greatest_majority (V0) is superseded: Membership::greatest_majority_value and
# its test were deleted by the update (see spec/validation-summary.md).

# --- Update-focused scenarios (derived from the source diff) ---
run_case elect_multi 'engine::elect_test::test_elect' Elect
run_case vote_resp 'engine::handle_vote_resp_test::test_handle_vote_resp' HandleVoteResp
run_case leader_fast_commit 'engine::leader_append_entries_test::test_leader_append_entries_fast_commit' LeaderAppend
run_case leader_fast_commit_no_voter_change 'engine::leader_append_entries_test::test_leader_append_entries_fast_commit_membership_no_voter_change' LeaderAppend
run_case leader_fast_commit_voter_change_to_1 'engine::leader_append_entries_test::test_leader_append_entries_fast_commit_if_membership_voter_change_to_1' LeaderAppend
run_case update_progress 'engine::update_progress_test::test_update_progress_update_leader_progress' UpdateProgress
run_case update_progress_no_leader 'engine::update_progress_test::test_update_progress_no_leader' UpdateProgress
run_case update_effective_leader 'engine::update_effective_membership_test::test_update_effective_membership_for_leader' UpdateEffectiveMembership
run_case update_effective_learner 'engine::update_effective_membership_test::test_update_effective_membership_at_index_0_is_allowed' UpdateEffectiveMembership
run_case progress_upgrade 'progress::t::vec_progress_upgrade_quorum_set' ProgressUpdate,ProgressUpgrade
run_case follower_commit_no_update 'engine::follower_commit_entries_test::test_follower_commit_entries_no_update' FollowerCommit
run_case follower_commit_lt_last 'engine::follower_commit_entries_test::test_follower_commit_entries_lt_last_entry' FollowerCommit
run_case membership_change_then_acks 'engine::specula_trace_test::specula_trace_leader_membership_change_then_acks' LeaderAppend,UpdateProgress

for trace_file in "$trace_dir"/*.ndjson; do
    while IFS= read -r line; do
        printf '%s\n' "$line" | python3 -I -m json.tool >/dev/null
    done < "$trace_file"
done
