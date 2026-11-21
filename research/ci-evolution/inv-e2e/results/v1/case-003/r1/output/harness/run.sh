#!/usr/bin/env bash
# V1 harness: apply instrumentation to the updated source, run the prior
# regression scenarios and the update-focused scenarios, write fresh traces.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_root="$(cd "$script_dir/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$output_root/artifact}"
trace_dir="${SPECULA_TRACE_DIR:-$output_root/traces}"
log_dir="${SPECULA_LOG_DIR:-$output_root/spec/output}"
log_prefix="${SPECULA_LOG_PREFIX:-harness}"
only="${SPECULA_ONLY:-all}"   # all | prior | update

"$script_dir/apply.sh" "$work_source"
mkdir -p "$trace_dir" "$log_dir"
export GOFLAGS="${GOFLAGS:-}"

check_trace() {
    local trace_file="$1"
    test -s "$trace_file"
    jq -e -s 'length > 0 and all(.[]; .tag == "trace" and (.event.name | type == "string") and (.event.state | type == "object"))' \
        "$trace_file" >/dev/null
}

run_case() {
    local name="$1" package="$2" test_filter="$3" extra_env="${4:-}"
    local trace_file="$trace_dir/$name.ndjson"
    local log_file="$log_dir/${log_prefix}-${name//_/-}.log"
    : > "$trace_file"
    (
        cd "$work_source"
        set -o pipefail
        echo "# command: (cd $work_source && timeout 10m env SPECULA_TRACE_FILE=$trace_file $extra_env go test -mod=readonly $package -run '$test_filter' -count=1 -v)"
        timeout 10m env SPECULA_TRACE_FILE="$trace_file" $extra_env \
            go test -mod=readonly "$package" -run "$test_filter" -count=1 -v 2>&1
        echo "# exit: $?"
    ) > "$log_file" 2>&1 || { echo "$name: go test FAILED (see $log_file)"; tail -20 "$log_file"; return 1; }
    check_trace "$trace_file"
    echo "$name: $(wc -l < "$trace_file") trace events"
}

if [ "$only" = all ] || [ "$only" = prior ]; then
    # Prior (V0) regression scenarios, unchanged entry points.
    run_case apply_valid ./internal/state '^TestSpeculaTraceApplyValidUpdate$'
    run_case apply_rejected ./internal/state '^TestSpeculaTraceApplyRejectedUpdate$'
    run_case replay_app_only ./internal/consensus '^TestHandshakeReplaySome$/^mode_0_single$'
    run_case replay_real ./internal/consensus '^TestHandshakeReplayNone$/^mode_1_single$'
    run_case replay_mock ./internal/consensus '^TestHandshakeReplayNone$/^mode_2_single$'
    run_case replay_none ./internal/consensus '^TestHandshakeReplayNone$/^mode_0_single$'
fi

if [ "$only" = all ] || [ "$only" = update ]; then
    # V1 update-focused scenarios (types/params.go:208-261 rows).
    for c in enable_future enable_current echo_disabled echo_reached echo_future \
             disable_reached disable_future move_reached move_future negative; do
        run_case "ve_$c" ./internal/state "^TestSpeculaTraceVE\$/^${c}\$"
    done
    run_case ve_enable_then_echo ./internal/state '^TestSpeculaTraceVEEnableThenEcho$'
    run_case ve_echo_restart_apply ./internal/state '^TestSpeculaTraceVEEchoRestart$' \
        "SPECULA_TRACE_FILE_RESTART=$trace_dir/ve_echo_restart_handshake.ndjson"
    check_trace "$trace_dir/ve_echo_restart_handshake.ndjson"
    echo "ve_echo_restart_handshake: $(wc -l < "$trace_dir/ve_echo_restart_handshake.ndjson") trace events"
fi

echo "Fresh traces written below $trace_dir"
