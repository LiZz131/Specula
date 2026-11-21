#!/usr/bin/env bash
set -euo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
state_parent="/dev/shm/specula-v0-case-011"
run_state="$state_parent/mc-rerun-$$"
timeout_bound="${SPECULA_MC_TIMEOUT:-10m}"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"

cleanup() {
    rm -rf "$run_state"
}
trap cleanup EXIT INT TERM
mkdir -p "$run_state"
cd "$spec_dir"

timeout "$timeout_bound" java -XX:+UseParallelGC -cp "$classpath" tlc2.TLC \
    -workers 4 -coverage 1 -metadir "$run_state/primary" -config MC.cfg MC \
    2>&1 | tee output/model-check-rerun.log
timeout "$timeout_bound" java -XX:+UseParallelGC -cp "$classpath" tlc2.TLC \
    -workers 4 -coverage 1 -metadir "$run_state/membership" -config MC-membership.cfg MC \
    2>&1 | tee output/model-check-membership-rerun.log

rg -q 'Model checking completed. No error has been found.' output/model-check-rerun.log
rg -q 'Model checking completed. No error has been found.' output/model-check-membership-rerun.log
echo "Both bounded model-checking configurations completed without findings"
