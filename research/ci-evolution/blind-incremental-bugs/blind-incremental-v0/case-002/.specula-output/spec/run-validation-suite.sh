#!/usr/bin/env bash
set -uo pipefail

output_root=/work/prior/.specula-output
spec_root="$output_root/spec"
trace_root="$output_root/traces"
log_root="$spec_root/output/repair-suite"
meta_root="$spec_root/.tlc-repair-suite"
ledger="$log_root/command-results.ndjson"
classpath=/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar

mkdir -p "$log_root" "$meta_root"
: > "$ledger"

quote_command() {
    local rendered=""
    local arg
    for arg in "$@"; do
        printf -v arg '%q' "$arg"
        rendered+="${rendered:+ }$arg"
    done
    printf '%s' "$rendered"
}

record_result() {
    local id="$1"
    local kind="$2"
    local command="$3"
    local log="$4"
    local started="$5"
    local finished="$6"
    local exit_code="$7"
    local completed="$8"
    local zero_queue="$9"
    local no_error="${10}"
    local records="${11}"
    jq -cn \
        --arg id "$id" \
        --arg kind "$kind" \
        --arg command "$command" \
        --arg log "$log" \
        --arg started "$started" \
        --arg finished "$finished" \
        --argjson exit_code "$exit_code" \
        --argjson completed "$completed" \
        --argjson zero_queue "$zero_queue" \
        --argjson no_error "$no_error" \
        --argjson records "$records" \
        '{id:$id,kind:$kind,command:$command,log:$log,started_at_utc:$started,finished_at_utc:$finished,exit_code:$exit_code,natural_completion:$completed,zero_states_left_on_queue:$zero_queue,no_error:$no_error,trace_records:$records}' \
        >> "$ledger"
}

remove_meta() {
    local target="$1"
    case "$target" in
        "$meta_root"/*) test ! -d "$target" || find "$target" -depth -delete ;;
        *) return 64 ;;
    esac
}

run_tlc() {
    local id="$1"
    local kind="$2"
    local timeout_value="$3"
    local workers="$4"
    local module="$5"
    local config="$6"
    local json_path="$7"
    local records="$8"
    local log="$log_root/$id.log"
    local meta="$meta_root/$id"
    local -a command
    mkdir -p "$meta"
    if [[ -n "$json_path" ]]; then
        command=(timeout "$timeout_value" env "JSON=$json_path" java -Xmx8g -cp "$classpath" tlc2.TLC -cleanup -workers "$workers" -config "$config" -metadir "$meta" "$module")
    else
        command=(timeout "$timeout_value" java -Xmx16g -cp "$classpath" tlc2.TLC -cleanup -workers "$workers" -config "$config" -metadir "$meta" "$module")
    fi
    local command_text
    command_text="cd $(printf '%q' "$spec_root") && $(quote_command "${command[@]}")"
    local started finished exit_code completed=false zero_queue=false no_error=false
    started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf 'COMMAND: %s\n' "$command_text" > "$log"
    (
        cd "$spec_root"
        "${command[@]}"
    ) >> "$log" 2>&1
    exit_code=$?
    finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if rg -q 'Model checking completed\. No error has been found\.' "$log"; then
        completed=true
    fi
    if rg -q '[0-9]+ states generated, [0-9]+ distinct states found, 0 states left on queue\.' "$log"; then
        zero_queue=true
    fi
    if ! rg -qi '(^Error:|Invariant .* is violated|Temporal properties were violated|Exception|OutOfMemoryError)' "$log"; then
        no_error=true
    fi
    record_result "$id" "$kind" "$command_text" "spec/output/repair-suite/$id.log" "$started" "$finished" "$exit_code" "$completed" "$zero_queue" "$no_error" "$records"
    remove_meta "$meta"
    if [[ "$exit_code" -ne 0 || "$completed" != true || "$zero_queue" != true || "$no_error" != true ]]; then
        return 1
    fi
}

suite_status=0

for trace in \
    follower-diff.ndjson \
    follower-snap-attempt-001.ndjson \
    follower-snap.ndjson \
    leader-abandon-restart-recovery.ndjson \
    quorum-startup-mutation-shutdown.ndjson
do
    id="trace-${trace%.ndjson}"
    records=$(wc -l < "$trace_root/$trace")
    run_tlc "$id" trace-validation 300s 4 Trace.tla Trace.cfg "../traces/$trace" "$records" || suite_status=1
done

if [[ "$suite_status" -eq 0 ]]; then
    run_tlc base-canonical canonical-base-bfs 900s 16 base.tla base.cfg "" 0 || suite_status=1
fi

if [[ "$suite_status" -eq 0 ]]; then
    run_tlc mc-canonical canonical-mc-bfs 1800s 16 MC.tla MC.cfg "" 0 || suite_status=1
fi

test ! -d "$meta_root" || find "$meta_root" -depth -delete
exit "$suite_status"
