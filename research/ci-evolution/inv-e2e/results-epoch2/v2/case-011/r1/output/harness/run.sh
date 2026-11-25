#!/usr/bin/env bash
# One-command harness: apply test-only instrumentation to the updated source
# copy, build, run every scenario, and write fresh traces to ../traces.
set -euo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
harness_dir="$suite_root/harness"
work_source="${SPECULA_WORK_SOURCE:-$harness_dir/work/source-new}"
rust_toolchain="${SPECULA_RUST_TOOLCHAIN:-stable}"
target_dir="${SPECULA_CARGO_TARGET_DIR:-/work/.cache/cargo-target/new}"
trace_dir="$suite_root/traces"
run_log="$suite_root/spec/output/harness-run.log"
regression_cases=(start_election reject_stale_log grant_greater_vote establish_leader
                  append_joint_membership commit_membership restart_follower)
update_cases=(prevote_start prevote_tick_start prevote_single_voter prevote_req_grant
              prevote_req_reject_lease prevote_req_reject_log prevote_req_reject_vote
              prevote_resp_quorum_elect prevote_resp_reject_greater_log
              prevote_joint_grant_then_elect prevote_cleared_by_heartbeat
              prevote_cleared_by_vote_grant prevote_cleared_by_higher_vote_resp
              stale_prevote_after_win prevote_req_grant_empty_logs grant_vote_empty_logs)
cases=("${regression_cases[@]}" "${update_cases[@]}")

if [ ! -d "$work_source/openraft" ]; then
    mkdir -p "$work_source"
    git -C "$suite_root/artifact" archive HEAD | tar -x -C "$work_source"
fi
SPECULA_WORK_SOURCE="$work_source" "$harness_dir/apply-instrumentation.sh"
mkdir -p "$trace_dir" "$(dirname "$run_log")"
: > "$run_log"
echo "source: $(git -C "$suite_root/artifact" rev-parse HEAD) (artifact HEAD), work copy $work_source" | tee -a "$run_log"
for case_name in "${cases[@]}"; do rm -f "$trace_dir/$case_name.ndjson"; done

cd "$work_source"
RUSTUP_TOOLCHAIN="$rust_toolchain" CARGO_TARGET_DIR="$target_dir" \
    timeout 15m cargo test -p openraft --lib --no-run 2>&1 | tail -3 | tee -a "$run_log"
for case_name in "${cases[@]}"; do
    env SPECULA_TRACE_PATH="$trace_dir/$case_name.ndjson" RUSTUP_TOOLCHAIN="$rust_toolchain" \
        CARGO_TARGET_DIR="$target_dir" \
        timeout 5m cargo test -p openraft --lib \
        "engine::tests::specula_trace_test::specula_trace_$case_name" -- --exact --nocapture \
        2>&1 | grep -E "^test |test result" | tee -a "$run_log"
    test -s "$trace_dir/$case_name.ndjson"
    jq -e -s 'all(.[]; .tag == "trace" and (.event.pre | type == "object") and (.event.post | type == "object"))' \
        "$trace_dir/$case_name.ndjson" >/dev/null
    echo "trace $case_name: $(wc -l < "$trace_dir/$case_name.ndjson") events" | tee -a "$run_log"
done
echo "Generated ${#cases[@]} fresh traces in $trace_dir" | tee -a "$run_log"
