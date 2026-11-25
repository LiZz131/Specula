#!/usr/bin/env bash
# Code observations (divergence-evidence §6) for the model-checking findings:
# real Engine handlers of several nodes driven in-process.
set -euo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$suite_root/work-source}"
"$suite_root/harness/apply-instrumentation.sh"
cd "$work_source"
echo "source: $(git rev-parse HEAD) (+ instrumentation.patch)"
timeout 20m env RUSTUP_TOOLCHAIN="${SPECULA_RUST_TOOLCHAIN:-stable}" \
    CARGO_TARGET_DIR="${SPECULA_CARGO_TARGET_DIR:-/work/.cache/cargo-target/new}" \
    cargo test -p openraft --lib engine::tests::specula_observation_test -- --nocapture --test-threads 1
