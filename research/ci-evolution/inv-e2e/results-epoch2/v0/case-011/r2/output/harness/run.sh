#!/usr/bin/env bash
# One-command trace collection: apply instrumentation to a copy of the updated
# source, build, run every scenario, and write fresh NDJSON traces.
set -euo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_source="${SPECULAR_WORK_SOURCE:-$suite_root/work-source}"
rust_toolchain="${SPECULAR_RUST_TOOLCHAIN:-nightly-2026-03-01}"
trace_dir="$suite_root/traces"
run_log="$suite_root/spec/output/harness-run.log"
# Prior (V0) regression scenarios, then update-focused Pre-Vote scenarios.
prior_cases=(start_election reject_stale_log grant_greater_vote establish_leader
             append_joint_membership commit_membership restart_follower)
update_cases=(pre_elect_follower pre_elect_single_voter pre_vote_req_grant
              pre_vote_req_reject_lease pre_vote_req_reject_log pre_vote_req_reject_vote_order
              pre_vote_resp_quorum_elect pre_vote_resp_reject_greater_log
              pre_vote_resp_stale_ignored pre_vote_cleared_by_vote_grant
              candidate_prevote_then_leader)
cases=("${prior_cases[@]}" "${update_cases[@]}")

"$suite_root/harness/apply-instrumentation.sh"
mkdir -p "$trace_dir" "$(dirname "$run_log")"
: > "$run_log"
for case_name in "${cases[@]}"; do
    rm -f "$trace_dir/$case_name.ndjson"
done

cd "$work_source"
echo "## build $(date -u +%FT%TZ) toolchain=$rust_toolchain" | tee -a "$run_log"
RUSTUP_TOOLCHAIN="$rust_toolchain" timeout 30m cargo test -p openraft --lib --no-run 2>&1 | tail -3 | tee -a "$run_log"
for case_name in "${cases[@]}"; do
    echo "## case $case_name" | tee -a "$run_log"
    env SPECULAR_TRACE_PATH="$trace_dir/$case_name.ndjson" RUSTUP_TOOLCHAIN="$rust_toolchain" \
        timeout 5m cargo test -p openraft --lib \
        "engine::tests::specular_trace_test::specular_trace_$case_name" -- --exact --nocapture \
        2>&1 | tee -a "$run_log"
    test -s "$trace_dir/$case_name.ndjson"
    jq -e -s 'all(.tag == "trace" and (.event.pre | type == "object") and (.event.post | type == "object"))' \
        "$trace_dir/$case_name.ndjson" >/dev/null
    echo "records=$(wc -l < "$trace_dir/$case_name.ndjson")" | tee -a "$run_log"
done

echo "Generated ${#cases[@]} fresh traces in $trace_dir" | tee -a "$run_log"
