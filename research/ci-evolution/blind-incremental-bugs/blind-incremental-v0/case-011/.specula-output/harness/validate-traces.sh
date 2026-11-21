#!/usr/bin/env bash
set -euo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
state_parent="/dev/shm/specula-v0-case-011"
run_state="$state_parent/trace-rerun-$$"
timeout_bound="${SPECULA_TLC_TIMEOUT:-2m}"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
cases=(start_election reject_stale_log grant_greater_vote establish_leader append_joint_membership commit_membership restart_follower)

cleanup() {
    rm -rf "$run_state"
}
trap cleanup EXIT INT TERM
mkdir -p "$run_state"
cd "$spec_dir"

for case_name in "${cases[@]}"; do
    test -s "$suite_root/traces/$case_name.ndjson"
    timeout "$timeout_bound" env SPECULA_TRACE="$suite_root/traces/$case_name.ndjson" \
        java -XX:+UseParallelGC -cp "$classpath" tlc2.TLC -workers 1 \
        -metadir "$run_state/$case_name" -config Trace.cfg Trace \
        2>&1 | tee "output/trace-$case_name-rerun.log"
    rg -q 'Model checking completed. No error has been found.' "output/trace-$case_name-rerun.log"
done

echo "All ${#cases[@]} traces were fully consumed"

