#!/usr/bin/env bash
# One-command trace collection: apply instrumentation to the update revision,
# build, run every prior and update-focused scenario, and write fresh traces.
set -euo pipefail

harness_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
suite_root="$(cd "$harness_dir/.." && pwd)"
work_source="${SPECULAR_WORK_SOURCE:-$harness_dir/work-source}"
rust_toolchain="${SPECULAR_RUST_TOOLCHAIN:-nightly-2026-03-01}"
trace_dir="$suite_root/traces"
run_log="$suite_root/spec/output/harness-run.log"

# name:expected-event-count
cases=(
    # prior V0 regression scenarios
    start_election:1 reject_stale_log:1 grant_greater_vote:1 establish_leader:1
    append_joint_membership:1 commit_membership:1 restart_follower:1
    # update-focused Pre-Vote scenarios
    pre_elect_follower:1 pre_elect_single_voter:1
    pre_vote_req_grant:1 pre_vote_req_reject_lease:1 pre_vote_req_reject_log:1
    pre_vote_req_grant_empty_logs:1
    pre_vote_resp_quorum:1 pre_vote_resp_reject_greater_log:1
    pre_candidate_cleared_by_vote:2 pre_vote_after_establish:3
)

"$harness_dir/apply-instrumentation.sh"
mkdir -p "$trace_dir" "$(dirname "$run_log")"
: > "$run_log"
for entry in "${cases[@]}"; do
    rm -f "$trace_dir/${entry%%:*}.ndjson"
done

cd "$work_source"
echo "== build $(git rev-parse HEAD) toolchain=$rust_toolchain" | tee -a "$run_log"
RUSTUP_TOOLCHAIN="$rust_toolchain" timeout 30m cargo test -p openraft --lib --no-run 2>&1 | tee -a "$run_log"

for entry in "${cases[@]}"; do
    case_name="${entry%%:*}"
    expected="${entry##*:}"
    echo "== scenario $case_name" | tee -a "$run_log"
    env SPECULAR_TRACE_PATH="$trace_dir/$case_name.ndjson" RUSTUP_TOOLCHAIN="$rust_toolchain" \
        timeout 5m cargo test -p openraft --lib \
        "engine::tests::specular_trace_test::specular_trace_$case_name" -- --exact --nocapture \
        2>&1 | tee -a "$run_log"
    test -s "$trace_dir/$case_name.ndjson"
    test "$(wc -l < "$trace_dir/$case_name.ndjson")" -eq "$expected"
    jq -e '.tag == "trace" and (.event.pre | type == "object") and (.event.post | type == "object")
           and (.event.post | has("pre_candidate_active") and has("pre_grants") and has("send_pre_vote_pending"))' \
        "$trace_dir/$case_name.ndjson" >/dev/null
done

echo "Generated ${#cases[@]} fresh traces in $trace_dir" | tee -a "$run_log"
