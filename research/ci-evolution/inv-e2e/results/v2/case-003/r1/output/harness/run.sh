#!/usr/bin/env bash
# One-command trace collection for the case-003 updated revision.
# Applies patches/instrumentation.patch to the writable source tree (idempotent),
# runs every scenario in its own Go process with a 10-minute outer timeout, checks
# that every NDJSON file is nonempty and structurally valid, and keeps test logs.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_root="$(cd "$script_dir/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$output_root/artifact}"
trace_dir="$output_root/traces"
log_dir="$output_root/spec/output/harness"

"$script_dir/apply.sh" "$work_source"
mkdir -p "$trace_dir" "$log_dir"

run_case() {
    local name="$1"
    local package="$2"
    local test_filter="$3"
    local trace_file="$trace_dir/$name.ndjson"
    local log_file="$log_dir/harness-${name//_/-}.log"

    : > "$trace_file"
    (
        cd "$work_source"
        set -o pipefail
        echo "+ timeout 10m env SPECULA_TRACE_FILE=$trace_file go test -mod=readonly $package -run '$test_filter' -count=1 -v" > "$log_file"
        timeout 10m env SPECULA_TRACE_FILE="$trace_file" \
            go test -mod=readonly "$package" -run "$test_filter" -count=1 -v 2>&1 \
            | grep -E '^(=== RUN|--- (PASS|FAIL|SKIP)|PASS|FAIL|ok|panic)' >> "$log_file"
    )
    test -s "$trace_file"
    jq -e -s 'length > 0 and all(.[]; .tag == "trace" and (.event.name | type == "string") and (.event.state | type == "object") and (.event.state.veHist | type == "array") and (.event.state.activeParam | type == "object"))' \
        "$trace_file" >/dev/null
    echo "$name: $(wc -l < "$trace_file") trace events"
}

# Prior (V0) regression scenarios, rerun on the updated implementation.
run_case apply_valid ./internal/state '^TestSpeculaTraceApplyValidUpdate$'
run_case apply_rejected ./internal/state '^TestSpeculaTraceApplyRejectedUpdate$'
run_case replay_app_only ./internal/consensus '^TestHandshakeReplaySome$/^mode_0_single$'
run_case replay_real ./internal/consensus '^TestHandshakeReplayNone$/^mode_1_single$'
run_case replay_mock ./internal/consensus '^TestHandshakeReplayNone$/^mode_2_single$'
run_case replay_none ./internal/consensus '^TestHandshakeReplayNone$/^mode_0_single$'

# Update-focused scenarios (ValidateUpdate decision table through ApplyBlock).
run_case ve_enable_future ./internal/state '^TestSpeculaTraceVEEnableFuture$'
run_case ve_cancel_scheduled ./internal/state '^TestSpeculaTraceVECancelScheduled$'
run_case ve_unchanged_after_enable ./internal/state '^TestSpeculaTraceVEUnchangedAfterEnable$'
run_case ve_disable_after_enable ./internal/state '^TestSpeculaTraceVEDisableAfterEnable$'
run_case ve_modify_after_enable ./internal/state '^TestSpeculaTraceVEModifyAfterEnable$'
run_case ve_past_height ./internal/state '^TestSpeculaTraceVEPastHeight$'
run_case ve_negative ./internal/state '^TestSpeculaTraceVENegative$'

# Update x crash/recovery interaction scenarios (real Handshaker replay).
run_case replay_mock_ve_update ./internal/consensus '^TestSpeculaTraceReplayMockVEUpdate$'
run_case replay_real_ve_update ./internal/consensus '^TestSpeculaTraceReplayRealVEUpdate$'
run_case replay_real_ve_unchanged_rejected ./internal/consensus '^TestSpeculaTraceReplayRealVEUnchangedRejected$'

echo "Fresh traces written below $trace_dir"
