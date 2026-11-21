#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_root="$(cd "$script_dir/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-/work/work-source}"
trace_dir="$output_root/traces"
log_dir="$output_root/spec/output"

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
        timeout 10m env SPECULA_TRACE_FILE="$trace_file" \
            go test -mod=readonly "$package" -run "$test_filter" -count=1 2>&1 \
            | tee "$log_file"
    )
    test -s "$trace_file"
    jq -e -s 'length > 0 and all(.[]; .tag == "trace" and (.event.name | type == "string") and (.event.state | type == "object"))' \
        "$trace_file" >/dev/null
    echo "$name: $(wc -l < "$trace_file") trace events"
}

run_case apply_valid ./internal/state '^TestSpeculaTraceApplyValidUpdate$'
run_case apply_rejected ./internal/state '^TestSpeculaTraceApplyRejectedUpdate$'
run_case replay_app_only ./internal/consensus '^TestHandshakeReplaySome$/^mode_0_single$'
run_case replay_real ./internal/consensus '^TestHandshakeReplayNone$/^mode_1_single$'
run_case replay_mock ./internal/consensus '^TestHandshakeReplayNone$/^mode_2_single$'
run_case replay_none ./internal/consensus '^TestHandshakeReplayNone$/^mode_0_single$'

echo "Fresh traces written below $trace_dir"

