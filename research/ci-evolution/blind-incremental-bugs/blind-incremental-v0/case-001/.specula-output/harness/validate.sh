#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
output_root=$(cd -- "$script_dir/.." && pwd)
spec_dir="$output_root/spec"
trace_dir="$output_root/traces"
log_dir="$spec_dir/output"
state_root=/dev/shm/specula-v0-case-001
tla_cp=/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar

cleanup() {
    if test -d "$state_root"; then
        find "$state_root" -depth -delete 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM
cleanup
mkdir -p "$log_dir"

for trace_file in "$trace_dir"/*.ndjson; do
    trace_name=$(basename -- "$trace_file" .ndjson)
    state_dir="$state_root/trace-$trace_name"
    mkdir -p "$state_dir"
    (
        cd -- "$spec_dir"
        JSON="$trace_file" timeout 2m java -XX:+UseParallelGC -cp "$tla_cp" \
            tlc2.TLC -workers 1 -metadir "$state_dir" -config Trace.cfg Trace.tla
    ) 2>&1 | tee "$log_dir/trace-$trace_name.log"
    find "$state_dir" -depth -delete
done

state_dir="$state_root/model-check"
mkdir -p "$state_dir"
(
    cd -- "$spec_dir"
    timeout 5m java -XX:+UseParallelGC -cp "$tla_cp" \
        tlc2.TLC -workers auto -coverage 0 -metadir "$state_dir" \
        -config MC.cfg MC.tla
) 2>&1 | tee "$log_dir/model-check.log"
