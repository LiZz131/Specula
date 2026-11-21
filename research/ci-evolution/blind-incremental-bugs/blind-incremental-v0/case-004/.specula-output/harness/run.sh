#!/usr/bin/env bash
set -euo pipefail

work_tree=/work/work-source
output_root=/work/prior/.specula-output
trace_dir="$output_root/traces"
log_file="$output_root/spec/output/harness.log"

mkdir -p "$trace_dir" "$output_root/spec/output" "$output_root/build/cargo-target"
: >"$log_file"

run_one() {
    local test_name="$1"
    local trace_name="$2"
    local trace_file="$trace_dir/$trace_name.ndjson"
    rm -f "$trace_file"
    (
        cd "$work_tree"
        timeout 15m env \
            CARGO_TARGET_DIR="$output_root/build/cargo-target" \
            SPECULA_TRACE_FILE="$trace_file" \
            cargo +1.95.0 test -p openraft --lib \
                "engine::specula_trace_tests::$test_name" -- \
                --exact --nocapture --test-threads=1
    ) 2>&1 | tee -a "$log_file"
    test -s "$trace_file"
}

run_one specula_trace_election election
run_one specula_trace_vote_request vote-request
run_one specula_trace_follower_append follower-append
run_one specula_trace_learner_membership learner-membership
run_one specula_trace_joint_membership joint-membership
run_one specula_trace_uniform_membership uniform-membership
run_one specula_trace_partial_replication partial-replication
run_one specula_trace_restart restart

printf '%s\n' "collected 8 nonempty traces" | tee -a "$log_file"
