#!/usr/bin/env bash
# Reproduction tests for MC-1 / CR-1. They assert the promised behavior and are
# EXPECTED TO FAIL on the defective revision; the control must pass.
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$suite_root/work-source}"
tc="${SPECULA_RUST_TOOLCHAIN:-stable}"
"$suite_root/harness/apply-instrumentation.sh"
cd "$work_source"
RUST_BACKTRACE=1 timeout 40m env RUSTUP_TOOLCHAIN="$tc" cargo test -p openraft --lib specula_repro_ -- --nocapture --skip specula_repro_stale_pre_vote_grant > "$suite_root/spec/output/repro-engine.log" 2>&1
RUST_BACKTRACE=1 timeout 40m env RUSTUP_TOOLCHAIN="$tc" cargo test -p openraft --lib specula_control -- --nocapture > "$suite_root/spec/output/repro-engine-control.log" 2>&1
RUST_BACKTRACE=1 timeout 40m env RUSTUP_TOOLCHAIN="$tc" cargo test -p tests --test elect specula_stale_pre_vote_round_does -- --nocapture > "$suite_root/spec/output/repro-integration.log" 2>&1
RUST_BACKTRACE=1 timeout 40m env RUSTUP_TOOLCHAIN="$tc" cargo test -p tests --test elect specula_timer -- --nocapture > "$suite_root/spec/output/repro-integration-timer.log" 2>&1
RUST_BACKTRACE=1 timeout 40m env RUSTUP_TOOLCHAIN="$tc" cargo test -p openraft --lib specula_repro_stale_pre_vote_grant -- --nocapture > "$suite_root/spec/output/repro-engine-stale-grant.log" 2>&1
RUST_BACKTRACE=1 timeout 40m env RUSTUP_TOOLCHAIN="$tc" cargo test -p tests --test elect specula_stale_pre_vote_grant -- --nocapture > "$suite_root/spec/output/repro-integration-stale-grant.log" 2>&1
RUST_BACKTRACE=1 timeout 40m env RUSTUP_TOOLCHAIN="$tc" cargo test -p tests --test elect t94_specula -- --nocapture --test-threads=1 > "$suite_root/spec/output/repro-integration-term-stall.log" 2>&1
grep -hE "^test .*(ok|FAILED)$|SPECULA_OBSERVATION|panicked at|leader.vote" "$suite_root"/spec/output/repro-*.log
