#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
output_root=$(cd -- "$script_dir/.." && pwd)
work_source=${SPECULA_WORK_SOURCE:-/work/work-source}
trace_dir="$output_root/traces"
log_file="$output_root/spec/output/trace-collection.log"

"$script_dir/apply.sh"
mkdir -p "$trace_dir" "$(dirname -- "$log_file")"
find "$trace_dir" -maxdepth 1 -type f -name '*.ndjson' -delete
: > "$log_file"

run_case() {
    local trace_name=$1
    local event_name=$2
    local test_filter=$3
    local trace_file="$trace_dir/$trace_name.ndjson"

    (
        cd -- "$work_source"
        SPECULA_TRACE="$trace_file" \
        SPECULA_EVENT_FILTER="$event_name" \
        timeout 5m cargo test -p openraft --lib "$test_filter" -- --exact
    ) 2>&1 | tee -a "$log_file"

    test -s "$trace_file"
    jq -e . "$trace_file" >/dev/null
}

run_case initialization EngineInitialize \
    engine::tests::initialize_test::test_initialize_single_node
run_case election EngineElect \
    engine::tests::elect_test::test_elect_multi_node_enter_candidate
run_case leader-establishment HandleVoteResponse \
    engine::tests::handle_vote_resp_test::test_handle_vote_resp_equal_vote
run_case append-replication EngineAppendEntries \
    engine::tests::append_entries_test::test_append_entries_prev_log_id_is_committed
run_case io-lifecycle IOAccept,IOSubmit,IOFlush \
    raft_state::io_state::io_progress::tests::test_monotonic_updates

for trace_file in "$trace_dir"/*.ndjson; do
    printf '%s: %s event(s)\n' "$(basename -- "$trace_file")" "$(wc -l < "$trace_file")"
done | tee -a "$log_file"
