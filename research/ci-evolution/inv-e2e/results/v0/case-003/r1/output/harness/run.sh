#!/usr/bin/env bash
# V1 harness: rebased V0 harness + update-focused scenarios.
# One command: apply instrumentation to the updated source, build, run the
# prior and update scenarios, validate trace structure, remove instrumentation.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_root="$(cd "$script_dir/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$output_root/artifact}"
trace_dir="$output_root/traces"
log_dir="$output_root/spec/output"

"$script_dir/apply.sh" "$work_source"
if [ "${SPECULA_KEEP_INSTRUMENTATION:-0}" != "1" ]; then
    trap '"$script_dir/clean.sh" "$work_source"' EXIT
fi
mkdir -p "$trace_dir" "$log_dir"

(cd "$work_source" && timeout 10m go build ./internal/... ) 2>&1 | tee "$log_dir/harness-build.log"

check_trace() {
    local trace_file="$1"
    test -s "$trace_file"
    jq -e -s 'length > 0 and all(.[]; .tag == "trace" and (.event.name | type == "string") and (.event.state | type == "object") and (.event.state.activeParam | type == "object") and (.event.state.pendingParam | type == "object"))' \
        "$trace_file" >/dev/null
    echo "$(basename "$trace_file"): $(wc -l < "$trace_file") trace events"
}

run_case() {
    local name="$1" package="$2" test_filter="$3" prefix="${4:-}"
    local trace_file="$trace_dir/$name.ndjson"
    local log_file="$log_dir/harness-${name//_/-}.log"
    local prefix_file=""
    : > "$trace_file"
    if [ -n "$prefix" ]; then prefix_file="$trace_dir/$prefix.ndjson"; : > "$prefix_file"; fi
    (
        cd "$work_source"
        set -o pipefail
        echo "cmd: timeout 10m env SPECULA_TRACE_FILE=$trace_file SPECULA_TRACE_PREFIX_FILE=$prefix_file go test -mod=readonly $package -run '$test_filter' -count=1 -v"
        timeout 10m env SPECULA_TRACE_FILE="$trace_file" SPECULA_TRACE_PREFIX_FILE="$prefix_file" \
            go test -mod=readonly "$package" -run "$test_filter" -count=1 -v 2>&1
    ) | tee "$log_file"
    [ -z "$prefix_file" ] || check_trace "$prefix_file"
    check_trace "$trace_file"
}

# Prior (V0) regression scenarios, rerun on the updated implementation.
run_case apply_valid ./internal/state '^TestSpeculaTraceApplyValidUpdate$'
run_case apply_rejected ./internal/state '^TestSpeculaTraceApplyRejectedUpdate$'
run_case replay_app_only ./internal/consensus '^TestHandshakeReplaySome$/^mode_0_single$'
run_case replay_real ./internal/consensus '^TestHandshakeReplayNone$/^mode_1_single$'
run_case replay_mock ./internal/consensus '^TestHandshakeReplayNone$/^mode_2_single$'
run_case replay_none ./internal/consensus '^TestHandshakeReplayNone$/^mode_0_single$'

# V1 update-focused scenarios (types/params.go:208-261).
run_case apply_ve_enable_from_zero ./internal/state '^TestSpeculaTraceApplyVEEnableFromZero$'
run_case apply_ve_past_height ./internal/state '^TestSpeculaTraceApplyVEPastHeight$'
run_case apply_ve_cancel_future ./internal/state '^TestSpeculaTraceApplyVECancelFuture$'
run_case apply_ve_modify_after_enable ./internal/state '^TestSpeculaTraceApplyVEModifyAfterEnable$'
run_case apply_ve_unchanged_after_enable ./internal/state '^TestSpeculaTraceApplyVEUnchangedAfterEnable$'
run_case apply_ve_unchanged_echo ./internal/state '^TestSpeculaTraceApplyVEUnchangedEcho$'
run_case apply_ve_zero_to_zero ./internal/state '^TestSpeculaTraceApplyVEZeroToZero$'
run_case apply_ve_disable_after_enable ./internal/state '^TestSpeculaTraceApplyVEDisableAfterEnable$'
run_case apply_ve_modify_future ./internal/state '^TestSpeculaTraceApplyVEModifyFuture$'
run_case apply_ve_negative ./internal/state '^TestSpeculaTraceApplyVENegative$'
run_case replay_ve_unchanged_restart ./internal/consensus '^TestSpeculaTraceReplayVEUnchanged$' replay_ve_unchanged_prefix
run_case replay_mock_ve_enable_restart ./internal/consensus '^TestSpeculaTraceReplayMockVEEnable$' replay_mock_ve_enable_prefix

echo "Fresh traces written below $trace_dir"
