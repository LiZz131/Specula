#!/usr/bin/env bash
# End-to-end RaftCore reproductions of MC-1 and MC-2 on the updated source.
# Each test asserts the correct behavior and therefore FAILS on a revision that has the defect.
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$suite_root/artifact}"
rust_toolchain="${SPECULA_RUST_TOOLCHAIN:-stable}"
out="$suite_root/spec/output"
SPECULA_WORK_SOURCE="$work_source" bash "$suite_root/harness/apply-instrumentation.sh"
cd "$work_source"
for t in "MC-1 t90_specula_repro" "MC-2 t91_specula"; do
    set -- $t
    env RUSTUP_TOOLCHAIN="$rust_toolchain" timeout 10m cargo test -p tests --test elect "$2" -- --nocapture \
        > "$out/repro-$1-latest.log" 2>&1
    echo "$1 exit=$? (101 = assertion failed: defect present)"
    grep -E 'SPECULA_REPRO|panicked at' "$out/repro-$1-latest.log"
done
