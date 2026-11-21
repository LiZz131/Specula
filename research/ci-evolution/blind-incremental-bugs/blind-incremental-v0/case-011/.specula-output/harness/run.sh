#!/usr/bin/env bash
set -euo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-/work/work-source}"
rust_toolchain="${SPECULA_RUST_TOOLCHAIN:-nightly-2025-12-31}"
trace_dir="$suite_root/traces"
run_log="$suite_root/spec/output/harness-rerun.log"
cases=(start_election reject_stale_log grant_greater_vote establish_leader append_joint_membership commit_membership restart_follower)

mkdir -p "$trace_dir" "$(dirname "$run_log")"
for case_name in "${cases[@]}"; do
    rm -f "$trace_dir/$case_name.ndjson"
done

cd "$work_source"
for case_name in "${cases[@]}"; do
    env SPECULA_TRACE_PATH="$trace_dir/$case_name.ndjson" RUSTUP_TOOLCHAIN="$rust_toolchain" \
        timeout 2m cargo test -p openraft --lib \
        "engine::tests::specula_trace_test::specula_trace_$case_name" -- --exact --nocapture \
        2>&1 | tee -a "$run_log"
    test -s "$trace_dir/$case_name.ndjson"
    test "$(wc -l < "$trace_dir/$case_name.ndjson")" -eq 1
    jq -e '.tag == "trace" and (.event.pre | type == "object") and (.event.post | type == "object")' \
        "$trace_dir/$case_name.ndjson" >/dev/null
done

echo "Generated ${#cases[@]} fresh traces in $trace_dir"

