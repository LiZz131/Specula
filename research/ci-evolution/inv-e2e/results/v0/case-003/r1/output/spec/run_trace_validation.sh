#!/usr/bin/env bash
# Usage: run_trace_validation.sh <trace-name> [<trace-name> ...]
# Real TLC trace validation of traces/<name>.ndjson against Trace.tla/Trace.cfg.
# States under /dev/shm/specula-e2e-case-003/, logs in spec/output/, metadir
# removed after every run.
set -uo pipefail
spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lib=/work/lib
state_root=/dev/shm/specula-e2e-case-003
mkdir -p "$state_root" "$spec_dir/output"
rc_all=0
for name in "$@"; do
    trace="${TRACE_DIR:-$spec_dir/../traces}/$name.ndjson"
    meta="$state_root/trace-$name-$$"
    log="${LOG_DIR:-$spec_dir/output}/trace-v1-$name.log"
    {
        echo "cmd: cd $spec_dir && JSON=$trace timeout 10m java -XX:+UseParallelGC -Xmx2g -cp $lib/tla2tools.jar:$lib/CommunityModules-deps.jar tlc2.TLC -config Trace.cfg -metadir $meta -workers 1 -cleanup Trace.tla"
        echo "trace sha256: $(sha256sum "$trace" | cut -d' ' -f1)  events: $(wc -l < "$trace")"
        echo "spec sha256: base=$(sha256sum "$spec_dir/base.tla" | cut -c1-16) Trace=$(sha256sum "$spec_dir/Trace.tla" | cut -c1-16) cfg=$(sha256sum "$spec_dir/Trace.cfg" | cut -c1-16)"
    } > "$log"
    (cd "$spec_dir" && JSON="$trace" timeout 10m java -XX:+UseParallelGC -Xmx2g \
        -cp "$lib/tla2tools.jar:$lib/CommunityModules-deps.jar" tlc2.TLC \
        -config Trace.cfg -metadir "$meta" -workers 1 -cleanup Trace.tla) >> "$log" 2>&1
    rc=$?
    echo "tlc exit=$rc" >> "$log"
    rm -rf "$meta"
    if [ $rc -eq 0 ] && grep -q "Model checking completed. No error has been found." "$log"; then
        depth=$(grep -o "depth of the complete state graph search is [0-9]*" "$log" | grep -o "[0-9]*$")
        echo "PASS $name events=$(wc -l < "$trace") depth=$depth"
    else
        echo "FAIL $name (exit $rc) -> $log"; rc_all=1
    fi
done
exit $rc_all
