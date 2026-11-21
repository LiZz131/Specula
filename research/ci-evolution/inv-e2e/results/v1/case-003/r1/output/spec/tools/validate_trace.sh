#!/usr/bin/env bash
# usage: tools/validate_trace.sh <trace-name> [log-prefix]
# Runs real TLC trace validation (Trace.tla/Trace.cfg, PROPERTIES TraceMatched)
# for ../traces/<trace-name>.ndjson; logs to output/<prefix>-<trace-name>.log
set -u
spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="$1"; prefix="${2:-trace}"
trace="${TRACE_DIR:-$spec_dir/../traces}/$name.ndjson"
JSON="$trace" TLC_OUTER_TIMEOUT=15m TLC_HEAP=4g "$spec_dir/tools/run_tlc.sh" "$prefix-$name" Trace.tla Trace.cfg -workers 1
rc=$?
log="$spec_dir/output/$prefix-$name.log"
events=$(grep -c '"tag"' "$trace" 2>/dev/null || echo 0)
if [ $rc -eq 0 ] && grep -q "Model checking completed. No error has been found." "$log"; then
  depth=$(grep -o "The depth of the complete state graph search is [0-9]*" "$log" | grep -o "[0-9]*$")
  echo "RESULT $name: MATCHED events=$events depth=$depth"
else
  echo "RESULT $name: FAILED rc=$rc events=$events (see output/$prefix-$name.log)"
fi
exit $rc
