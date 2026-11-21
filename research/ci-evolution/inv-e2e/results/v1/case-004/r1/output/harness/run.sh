#!/usr/bin/env bash
# Specula harness (V0 harness rebased onto the update revision).
# One command: apply instrumentation to ../artifact, build, run every scenario, write fresh traces.
#   unit layer   -> ../traces/<name>.ndjson          (Engine calls, prior V0 scenarios + update ones)
#   window layer -> ../traces/window/<scenario>/*.ndjson  (RaftCore TransferLeader/vote windows)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
output_root="$(cd "$here/.." && pwd)"
work_tree="$output_root/artifact"
trace_dir="$output_root/traces"
win_root="$trace_dir/window"
log_dir="$output_root/spec/output"
log_file="$log_dir/harness.log"
toolchain="${SPECULA_TOOLCHAIN:-stable}"   # artifact pins nightly-2024-03-20, not installable offline
export CARGO_TARGET_DIR="$output_root/build/cargo-target"

mkdir -p "$trace_dir" "$win_root" "$log_dir" "$CARGO_TARGET_DIR"
: >"$log_file"
log() { printf '%s\n' "$*" | tee -a "$log_file"; }

cd "$work_tree"
log "# source: $(git rev-parse HEAD) ($(git log -1 --format=%s))"
if git apply --check "$here/instrumentation.patch" 2>/dev/null; then
    git apply "$here/instrumentation.patch"; log "# instrumentation applied"
elif git apply --reverse --check "$here/instrumentation.patch" 2>/dev/null; then
    log "# instrumentation already applied"
else
    log "# ERROR: instrumentation.patch neither applies nor is applied"; exit 1
fi
[ -f Cargo.lock ] || cp "$here/Cargo.lock" Cargo.lock   # dependency versions used for the recorded run
log "# toolchain: $(cargo +"$toolchain" --version)"

run_unit() {
    local test_name="$1" trace_name="$2" trace_file="$trace_dir/$2.ndjson"
    rm -f "$trace_file"
    log "## unit $test_name -> traces/$trace_name.ndjson"
    timeout 15m env SPECULA_TRACE_FILE="$trace_file" \
        cargo +"$toolchain" test -p openraft --lib "engine::specula_trace_tests::$test_name" -- \
        --exact --nocapture --test-threads=1 2>&1 | tee -a "$log_file"
    test -s "$trace_file"
}

run_window() {
    local test_path="$1" label="$2" dir="$win_root/$2"
    rm -rf "$dir"; mkdir -p "$dir"
    log "## window $test_path -> traces/window/$label/"
    timeout 15m env SPECULA_TRACE_DIR="$dir" RUST_TEST_THREADS=1 \
        cargo +"$toolchain" test -p tests --test client_api --features specula-trace "$test_path" -- \
        --exact --nocapture --test-threads=1 2>&1 | tee -a "$log_file"
    ls "$dir"/*.ndjson >/dev/null
}

# Prior V0 regression scenarios (rerun on the update revision).
run_unit specula_trace_election election
run_unit specula_trace_vote_request vote-request
run_unit specula_trace_follower_append follower-append
run_unit specula_trace_learner_membership learner-membership
run_unit specula_trace_joint_membership joint-membership
run_unit specula_trace_uniform_membership uniform-membership
run_unit specula_trace_partial_replication partial-replication
run_unit specula_trace_restart restart

# Update-focused unit scenarios.
run_unit specula_trace_elect_learner elect-learner
run_unit specula_trace_elect_absent elect-absent
run_unit specula_trace_follower_membership follower-membership
run_unit specula_trace_vote_request_logid vote-request-logid

# Update-focused RaftCore window scenarios (live 3/4-node memstore clusters).
run_window t14_transfer_leader::transfer_leader t14-transfer-to-voter
run_window t99_specula_transfer_leader::specula_transfer_leader_to_learner t99-transfer-to-learner

n_unit=$(ls "$trace_dir"/*.ndjson | wc -l)
n_win=$(find "$win_root" -name '*.ndjson' | wc -l)
log "collected $n_unit nonempty unit traces and $n_win window traces"
