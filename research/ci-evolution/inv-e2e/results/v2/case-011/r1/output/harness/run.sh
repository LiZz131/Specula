#!/usr/bin/env bash
# One-command harness: apply instrumentation to the updated source, build,
# run every scenario, and collect fresh NDJSON traces into traces/.
set -euo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$suite_root/artifact}"
# nightly-2026-03-01 (rust-toolchain) is not installed and /opt/rustup is
# read-only; the installed stable toolchain builds the crate.
rust_toolchain="${SPECULA_RUST_TOOLCHAIN:-stable}"
trace_dir="$suite_root/traces"
out_dir="$suite_root/spec/output"
run_log="$out_dir/harness-run.log"
obs_log="$out_dir/harness-observations.log"

prior_cases=(start_election reject_stale_log grant_greater_vote establish_leader
             append_joint_membership commit_membership restart_follower)
update_cases=(prevote_timer_multi prevote_external_single_voter prevote_req_reject_lease
              prevote_req_reject_log prevote_req_grant prevote_resp_reject_then_quorum
              prevote_cancelled_by_vote_grant prevote_stale_round_after_leadership
              prevote_round_reuses_probe)
observations=(observe_stale_prevote_on_leader observe_prevote_grant_from_non_member)

mkdir -p "$trace_dir" "$out_dir"
: > "$run_log"
: > "$obs_log"

SPECULA_WORK_SOURCE="$work_source" bash "$suite_root/harness/apply-instrumentation.sh" | tee -a "$run_log"

cd "$work_source"
echo "source HEAD: $(git rev-parse HEAD) ($(git log -1 --format=%s))" | tee -a "$run_log"
env RUSTUP_TOOLCHAIN="$rust_toolchain" timeout 20m cargo test -p openraft --lib --no-run 2>&1 | tail -3 | tee -a "$run_log"

for case_name in "${prior_cases[@]}" "${update_cases[@]}"; do
    rm -f "$trace_dir/$case_name.ndjson"
    env SPECULA_TRACE_PATH="$trace_dir/$case_name.ndjson" RUSTUP_TOOLCHAIN="$rust_toolchain" \
        timeout 5m cargo test -p openraft --lib \
        "engine::tests::specula_trace_test::specula_trace_$case_name" -- --exact --nocapture \
        >> "$run_log" 2>&1
    test -s "$trace_dir/$case_name.ndjson"
    jq -e '.tag == "trace" and (.event.pre | type == "object") and (.event.post | type == "object")' \
        "$trace_dir/$case_name.ndjson" >/dev/null
    echo "$case_name: $(wc -l < "$trace_dir/$case_name.ndjson") event(s)" | tee -a "$run_log"
done

for obs in "${observations[@]}"; do
    env RUSTUP_TOOLCHAIN="$rust_toolchain" timeout 5m cargo test -p openraft --lib \
        "engine::tests::specula_trace_test::specula_$obs" -- --exact --nocapture \
        > "$out_dir/harness-$obs.log" 2>&1 || true
    grep '^SPECULA_OBSERVATION' "$out_dir/harness-$obs.log" | tee -a "$obs_log"
done

total=$(( ${#prior_cases[@]} + ${#update_cases[@]} ))
echo "Generated $total fresh traces in $trace_dir" | tee -a "$run_log"
