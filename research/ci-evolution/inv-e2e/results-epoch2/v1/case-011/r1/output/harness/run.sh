#!/usr/bin/env bash
# One-command trace collection for the updated implementation:
# apply instrumentation -> build -> run every scenario -> fresh NDJSON traces.
set -euo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$suite_root/work-source}"
rust_toolchain="${SPECULA_RUST_TOOLCHAIN:-stable}"
target_dir="${SPECULA_CARGO_TARGET_DIR:-/work/.cache/cargo-target/new}"
trace_dir="$suite_root/traces"
log_dir="$suite_root/spec/output"
run_log="$log_dir/harness-run.log"
build_log="$log_dir/harness-build.log"

# V0 regression scenarios (setups unchanged) + update-focused scenarios.
v0_cases=(start_election reject_stale_log grant_greater_vote establish_leader
          append_joint_membership commit_membership restart_follower)
update_cases=(grant_empty_logs prevote_quorum_elect prevote_reject_higher_vote prevote_request_branches
              prevote_request_lease candidate_prevote_then_establish
              prevote_cleared_by_append prevote_cleared_by_vote_grant prevote_single_voter)
cases=("${v0_cases[@]}" "${update_cases[@]}")

mkdir -p "$trace_dir" "$log_dir"
"$suite_root/harness/apply-instrumentation.sh"

cd "$work_source"
echo "source: $(git rev-parse HEAD) (+ instrumentation.patch)" | tee "$build_log"
timeout 30m env RUSTUP_TOOLCHAIN="$rust_toolchain" CARGO_TARGET_DIR="$target_dir" \
    cargo test -p openraft --lib --no-run 2>&1 | tee -a "$build_log"

: > "$run_log"
for case_name in "${cases[@]}"; do
    rm -f "$trace_dir/$case_name.ndjson"
    env SPECULA_TRACE_PATH="$trace_dir/$case_name.ndjson" RUSTUP_TOOLCHAIN="$rust_toolchain" \
        CARGO_TARGET_DIR="$target_dir" \
        timeout 5m cargo test -p openraft --lib \
        "engine::tests::specula_trace_test::specula_trace_$case_name" -- --exact --nocapture \
        2>&1 | tee -a "$run_log"
    test -s "$trace_dir/$case_name.ndjson"
    jq -e -s 'all(.[]; .tag == "trace" and (.event.pre | type == "object") and (.event.post | type == "object"))' \
        "$trace_dir/$case_name.ndjson" >/dev/null
    echo "trace $case_name: $(wc -l < "$trace_dir/$case_name.ndjson") events" | tee -a "$run_log"
done

echo "Generated ${#cases[@]} fresh traces in $trace_dir"
