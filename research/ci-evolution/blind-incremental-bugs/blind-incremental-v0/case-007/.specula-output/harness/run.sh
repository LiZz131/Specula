#!/usr/bin/env bash
set -euo pipefail

work=/work/work-source
out=/work/prior/.specula-output

"$out/harness/apply.sh"
mkdir -p "$out/traces" "$out/spec/output"

run_case() {
    local trace_name=$1
    local target=$2
    local test_binary=$3
    local test_filter=$4
    local trace="$out/traces/$trace_name.ndjson"
    local log="$out/spec/output/harness-$trace_name.log"

    : >"$log"
    SPECULA_TRACE_FILE="$trace" SPECULA_TRACE_TARGET="$target" \
        timeout 300s cargo test -p tests --test "$test_binary" "$test_filter" -- --exact --nocapture \
        >"$log" 2>&1

    test -s "$trace"
    while IFS= read -r line; do
        jq -e '.tag == "trace" and (.event.name | type == "string")' <<<"$line" >/dev/null
    done <"$trace"
}

cd "$work"
run_case append-success 0 append_entries t10_stream_append::stream_append_success
run_case append-conflict 0 append_entries t10_stream_append::stream_append_conflict
run_case append-higher 0 append_entries t10_stream_append::stream_append_higher_vote
run_case partial-success 1 replication t10_append_entries_partial_success::append_entries_partial_success
run_case unreachable-backoff 2 replication t50_append_entries_backoff::append_entries_backoff
run_case retry-rejoin 0 replication t50_append_entries_backoff_rejoin::append_entries_backoff_rejoin
run_case isolated-learner 1 append_entries t30_replication_1_voter_to_isolated_learner::replication_1_voter_to_isolated_learner
run_case snapshot-success 1 snapshot_streaming t50_snapshot_when_lacking_log::switch_to_snapshot_replication_when_lacking_log

