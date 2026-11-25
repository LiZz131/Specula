#!/usr/bin/env bash
# One-command harness: apply instrumentation to the updated source, build the
# openraft lib tests, run every scenario in cases.txt, and write fresh traces.
set -euo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$suite_root/work-source}"
# nightly-2026-03-01 (rust-toolchain) is not installed and /opt/rustup is
# read-only; the installed stable toolchain builds this revision.
rust_toolchain="${SPECULA_RUST_TOOLCHAIN:-stable}"
trace_dir="$suite_root/traces"
log_dir="$suite_root/spec/output"
run_log="$log_dir/harness-run.log"
build_log="$log_dir/harness-build.log"
mapfile -t cases < <(grep -vE '^\s*(#|$)' "$suite_root/harness/cases.txt")

mkdir -p "$trace_dir" "$log_dir"
"$suite_root/harness/apply-instrumentation.sh"
for case_name in "${cases[@]}"; do
    rm -f "$trace_dir/$case_name.ndjson"
done
: > "$run_log"

cd "$work_source"
echo "source HEAD: $(git rev-parse HEAD)" | tee "$build_log"
timeout 40m env RUSTUP_TOOLCHAIN="$rust_toolchain" cargo test -p openraft --lib --no-run 2>&1 | tee -a "$build_log"
for case_name in "${cases[@]}"; do
    env SPECULA_TRACE_PATH="$trace_dir/$case_name.ndjson" RUSTUP_TOOLCHAIN="$rust_toolchain" \
        timeout 5m cargo test -p openraft --lib \
        "engine::tests::specula_trace_test::specula_trace_$case_name" -- --exact --nocapture \
        2>&1 | tee -a "$run_log"
    test -s "$trace_dir/$case_name.ndjson"
    jq -e -s 'length >= 1 and all(.[]; .tag == "trace" and (.event.pre | type == "object") and (.event.post | type == "object"))' \
        "$trace_dir/$case_name.ndjson" >/dev/null
done
echo "Generated ${#cases[@]} fresh traces in $trace_dir"
