#!/usr/bin/env bash
# One-command fresh trace collection on the updated implementation:
# apply instrumentation, build, run every scenario, check every trace file.
set -euo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$suite_root/work-source}"
rust_toolchain="${SPECULA_RUST_TOOLCHAIN:-stable}"
trace_dir="$suite_root/traces"
run_log="$suite_root/spec/output/v1-harness-run.log"

# name:expected_record_count
cases=(
  start_election:1 reject_stale_log:1 grant_greater_vote:1 establish_leader:1
  append_joint_membership:1 commit_membership:1 restart_follower:1
  pre_vote_req_grant:1 pre_vote_req_reject_lease:1 pre_vote_req_reject_log:1
  pre_vote_req_reject_vote:1 pre_elect_multi:1 pre_elect_single:1
  pre_vote_resp_quorum:3 pre_vote_resp_reject_greater_log:2
  pre_vote_superseded_by_vote_req:3 pre_vote_superseded_by_append:2
  pre_vote_superseded_by_elect:2 candidate_pre_vote_then_leader:5
  pre_vote_resp_joint_accumulate:3
)

"$suite_root/harness/apply-instrumentation.sh"
mkdir -p "$trace_dir" "$(dirname "$run_log")"
: > "$run_log"
for entry in "${cases[@]}"; do
    rm -f "$trace_dir/${entry%%:*}.ndjson" "$trace_dir/${entry%%:*}.ndjson.observation.json"
done

cd "$work_source"
echo "source HEAD: $(git rev-parse HEAD) ($(git log -1 --format=%s))" | tee -a "$run_log"
env RUSTUP_TOOLCHAIN="$rust_toolchain" timeout 20m cargo test -p openraft --lib --no-run 2>&1 | tail -3 | tee -a "$run_log"
for entry in "${cases[@]}"; do
    case_name="${entry%%:*}"; expected="${entry##*:}"
    env SPECULA_TRACE_PATH="$trace_dir/$case_name.ndjson" RUSTUP_TOOLCHAIN="$rust_toolchain" \
        timeout 5m cargo test -p openraft --lib \
        "engine::tests::specula_trace_test::specula_trace_$case_name" -- --exact --nocapture \
        2>&1 | grep -E "^test |test result" | tee -a "$run_log"
    test -s "$trace_dir/$case_name.ndjson"
    test "$(wc -l < "$trace_dir/$case_name.ndjson")" -eq "$expected"
    jq -e -s 'all(.[]; .tag == "trace" and (.event.pre | type == "object") and (.event.post | type == "object"))' \
        "$trace_dir/$case_name.ndjson" >/dev/null
done

echo "Generated ${#cases[@]} fresh traces in $trace_dir" | tee -a "$run_log"
