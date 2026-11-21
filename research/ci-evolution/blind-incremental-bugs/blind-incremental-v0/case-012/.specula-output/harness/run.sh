#!/usr/bin/env bash
set -euo pipefail

out_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_tree="${SPECULA_WORK_SOURCE:-/work/work-source}"
trace_dir="$out_dir/traces"
log_dir="$out_dir/spec/output"

bash "$out_dir/harness/apply.sh"
mkdir -p "$trace_dir" "$log_dir"

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
            cargo +nightly test -p openraft --lib "$test_name" -- --exact --nocapture
    ) >"$log_file" 2>&1
    timeout 30s python3 "$out_dir/harness/preprocess_trace.py" \
        "$raw_file" "$trace_file" "$event_filter"
    rm -f "$raw_file"
    test -s "$trace_file"
    echo "$name: $(wc -l < "$trace_file") events"
}

run_case election 'engine::specula_trace_test::specula_trace_election_single' Elect
run_case leader_append 'engine::leader_append_entries_test::test_leader_append_entries_normal' LeaderAppend
run_case leader_membership_append 'engine::leader_append_entries_test::test_leader_append_entries_with_membership' LeaderAppend
run_case follower_commit 'engine::follower_commit_entries_test::test_follower_commit_entries_gt_last_entry'
run_case membership_update 'engine::update_committed_membership_test::test_update_committed_membership_at_index_3'
run_case progress 'progress::t::vec_progress_update'
run_case quorum 'membership::effective_membership_test::test_effective_membership_majority'
run_case greatest_majority 'membership::membership_test::test_membership_greatest_majority_value'
run_case replication_state 'core::replication_state_test::test_is_line_rate'

for trace_file in "$trace_dir"/*.ndjson; do
    while IFS= read -r line; do
        printf '%s\n' "$line" | python3 -m json.tool >/dev/null
    done < "$trace_file"
done
