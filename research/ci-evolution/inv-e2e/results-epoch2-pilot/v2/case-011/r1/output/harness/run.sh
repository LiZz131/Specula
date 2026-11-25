#!/usr/bin/env bash
# One command: apply instrumentation to the current source copy, build, run
# every scenario in its own test process, and collect fresh NDJSON traces.
set -euo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_source="${SPECULAR_WORK_SOURCE:-$suite_root/work-source}"
trace_dir="$suite_root/traces"
run_log="$suite_root/spec/output/harness-run.log"
build_log="$suite_root/spec/output/harness-build.log"
source "$suite_root/harness/cases.sh"

mkdir -p "$trace_dir" "$(dirname "$run_log")"
bash "$suite_root/harness/apply-instrumentation.sh"
: > "$run_log"
echo "source HEAD: $(git -C "$work_source" rev-parse HEAD)" | tee -a "$run_log"

cd "$work_source"
timeout 30m cargo test -p openraft --lib --no-run 2>&1 | tee "$build_log"

for case_name in "${cases[@]}"; do
    rm -f "$trace_dir/$case_name.ndjson"
    env SPECULAR_TRACE_PATH="$trace_dir/$case_name.ndjson" \
        timeout 5m cargo test -p openraft --lib \
        "engine::tests::specular_trace_test::specular_trace_$case_name" -- --exact --nocapture \
        2>&1 | tee -a "$run_log"
    test -s "$trace_dir/$case_name.ndjson"
    jq -e -s 'all(.[]; .tag == "trace" and (.event.pre | type == "object") and (.event.post | type == "object"))' \
        "$trace_dir/$case_name.ndjson" >/dev/null
    echo "trace $case_name: $(wc -l < "$trace_dir/$case_name.ndjson") events" | tee -a "$run_log"
done

echo "Generated ${#cases[@]} fresh traces in $trace_dir" | tee -a "$run_log"
