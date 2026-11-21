#!/usr/bin/env bash
# Specula incremental harness (V0 harness rebased onto the `update` revision).
#
# One command: fresh copy of the updated source -> apply instrumentation.patch -> build ->
# run the 9 Engine unit scenarios and the 2 RaftCore integration scenarios -> write fresh
# NDJSON traces to ../traces/.  Every build/test step has an outer timeout.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
suite="$(cd "$here/.." && pwd)"
src="$suite/artifact"                      # updated source tree (commit `update`)
work_tree="$suite/build/work-source"       # disposable instrumented copy
target_dir="$suite/build/cargo-target"
trace_dir="$suite/traces"
raw_dir="$suite/traces/raw-core"
log_file="$suite/spec/output/harness.log"
toolchain="${SPECULA_TOOLCHAIN:-stable}"   # rust-toolchain pins an uninstalled nightly

mkdir -p "$trace_dir" "$raw_dir" "$suite/spec/output" "$target_dir"
: >"$log_file"
log() { printf '%s\n' "$*" | tee -a "$log_file"; }

log "source: $(git -C "$src" rev-parse HEAD) ($(git -C "$src" log -1 --format=%s))"
log "toolchain: $(cargo +"$toolchain" --version)"

rm -rf "$work_tree"
cp -a "$src" "$work_tree"
git -C "$work_tree" apply "$here/instrumentation.patch"
log "applied instrumentation.patch"

run_unit() {
    local test_name="$1" trace_name="$2"
    local trace_file="$trace_dir/$trace_name.ndjson"
    rm -f "$trace_file"
    (
        cd "$work_tree"
        timeout 15m env CARGO_TARGET_DIR="$target_dir" SPECULA_TRACE_FILE="$trace_file" \
            cargo +"$toolchain" test -p openraft --lib "engine::specula_trace_tests::$test_name" -- \
            --exact --nocapture --test-threads=1
    ) >>"$log_file" 2>&1
    test -s "$trace_file"
    log "unit $test_name -> $(basename "$trace_file") ($(wc -l <"$trace_file") lines)"
}

run_unit specula_trace_election election
run_unit specula_trace_vote_request vote-request
run_unit specula_trace_follower_append follower-append
run_unit specula_trace_learner_membership learner-membership
run_unit specula_trace_joint_membership joint-membership
run_unit specula_trace_uniform_membership uniform-membership
run_unit specula_trace_partial_replication partial-replication
run_unit specula_trace_restart restart
run_unit specula_trace_lease_touch lease-touch

run_core() {
    local test_path="$1" prefix="$2"
    local raw="$raw_dir/$prefix.raw.ndjson"
    rm -f "$raw" "$trace_dir/$prefix"-n*.ndjson
    (
        cd "$work_tree"
        timeout 20m env CARGO_TARGET_DIR="$target_dir" SPECULA_CORE_TRACE_FILE="$raw" \
            cargo +"$toolchain" test -p tests --test client_api "$test_path" -- \
            --exact --nocapture --test-threads=1
    ) >"$suite/spec/output/scenario-$prefix.log" 2>&1
    grep -h "SPECULA-OBS\|test result" "$suite/spec/output/scenario-$prefix.log" | tee -a "$log_file" || true
    test -s "$raw"
    python3 -I "$here/split_core_trace.py" "$raw" "$trace_dir" "$prefix" | tee -a "$log_file"
}

run_core t14_transfer_leader::transfer_leader core-t14
run_core t14_specula_transfer_to_learner::specula_transfer_leader_to_learner core-learner

log "fresh traces: $(ls "$trace_dir"/*.ndjson | wc -l)"
