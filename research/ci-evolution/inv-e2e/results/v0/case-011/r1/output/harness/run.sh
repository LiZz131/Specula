#!/usr/bin/env bash
# One-command harness: apply instrumentation to the updated source, build, run
# every scenario (prior V0 + update-focused), and write fresh NDJSON traces.
set -euo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$suite_root/work-source}"
rust_toolchain="${SPECULA_RUST_TOOLCHAIN:-stable}"
export CARGO_HOME="${CARGO_HOME:-/work/.cache/cargo}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/work/.cache/cargo-target}"
trace_dir="$suite_root/traces"
run_log="$suite_root/spec/output/harness-run.log"
source "$suite_root/harness/cases.sh"

SPECULA_WORK_SOURCE="$work_source" "$suite_root/harness/apply-instrumentation.sh"
mkdir -p "$trace_dir" "$(dirname "$run_log")"
: > "$run_log"
for case_name in "${cases[@]}"; do
    rm -f "$trace_dir/$case_name.ndjson"
done

cd "$work_source"
echo "== build ($(date -u +%FT%TZ)) toolchain=$rust_toolchain HEAD=$(git rev-parse HEAD)" | tee -a "$run_log"
RUSTUP_TOOLCHAIN="$rust_toolchain" timeout 30m cargo test -p openraft --lib --no-run 2>&1 | tail -3 | tee -a "$run_log"
for case_name in "${cases[@]}"; do
    echo "== case $case_name" | tee -a "$run_log"
    env SPECULA_TRACE_PATH="$trace_dir/$case_name.ndjson" RUSTUP_TOOLCHAIN="$rust_toolchain" \
        timeout 5m cargo test -p openraft --lib \
        "engine::tests::specula_trace_test::specula_trace_$case_name" -- --exact --nocapture \
        2>&1 | grep -E "^test |test result|panicked|error" | tee -a "$run_log"
    test -s "$trace_dir/$case_name.ndjson"
    jq -e -s 'length > 0 and all(.tag == "trace" and (.event.pre | type == "object") and (.event.post | type == "object"))' \
        "$trace_dir/$case_name.ndjson" >/dev/null
    echo "   events: $(wc -l < "$trace_dir/$case_name.ndjson")" | tee -a "$run_log"
done
echo "Generated ${#cases[@]} fresh traces in $trace_dir" | tee -a "$run_log"
