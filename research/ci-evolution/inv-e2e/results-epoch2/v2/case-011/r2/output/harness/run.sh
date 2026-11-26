#!/usr/bin/env bash
# One-command fresh trace collection on the UPDATED source:
# apply instrumentation, build, run every scenario, check each trace is nonempty.
set -euo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_source="${SPECULAR_WORK_SOURCE:-$suite_root/work/source}"
rust_toolchain="${SPECULAR_RUST_TOOLCHAIN:-nightly-2026-03-01}"
trace_dir="$suite_root/traces"
run_log="$suite_root/spec/output/harness-run.log"
# name:expected-event-count
cases=(
  start_election:1 reject_stale_log:1 grant_greater_vote:1 establish_leader:1
  append_joint_membership:1 commit_membership:1 restart_follower:1
  pre_elect_multi:1 pre_elect_single_voter:1
  pre_vote_req_grant:1 pre_vote_req_lease_reject:1 pre_vote_req_stale_log:1
  pre_vote_resp_quorum:2 pre_vote_resp_reject_greater_log:2 pre_vote_resp_no_round:1
  pre_vote_cleared_by_vote_request:2 stale_pre_vote_after_leader:5
)

"$suite_root/harness/apply-instrumentation.sh"
mkdir -p "$trace_dir" "$(dirname "$run_log")"
: > "$run_log"
cd "$work_source"
env RUSTUP_TOOLCHAIN="$rust_toolchain" timeout 30m cargo test -p openraft --lib specular_trace --no-run >> "$run_log" 2>&1
for entry in "${cases[@]}"; do
    case_name="${entry%%:*}"; expected="${entry##*:}"
    rm -f "$trace_dir/$case_name.ndjson"
    env SPECULAR_TRACE_PATH="$trace_dir/$case_name.ndjson" RUSTUP_TOOLCHAIN="$rust_toolchain" \
        timeout 5m cargo test -p openraft --lib \
        "engine::tests::specular_trace_test::specular_trace_$case_name" -- --exact --nocapture \
        >> "$run_log" 2>&1
    test -s "$trace_dir/$case_name.ndjson"
    test "$(wc -l < "$trace_dir/$case_name.ndjson")" -eq "$expected"
    jq -e '.tag == "trace" and (.event.pre | type == "object") and (.event.post | type == "object")' \
        "$trace_dir/$case_name.ndjson" >/dev/null
    echo "trace $case_name: $expected event(s)" | tee -a "$run_log"
done
echo "Generated ${#cases[@]} fresh traces in $trace_dir" | tee -a "$run_log"
