#!/usr/bin/env bash
# Usage: validate_trace.sh <trace-basename-without-.ndjson> <logname>
set -uo pipefail
T=/work/current/.specula-output/traces/$1.ndjson
NAME=$2
JSON=$T /work/current/.specula-output/scripts/tlc.sh Trace Trace.cfg "$NAME" 20m -workers 1
LOG=/work/current/.specula-output/spec/output/$NAME.log
if grep -q "No error has been found" "$LOG" && grep -q "Model checking completed" "$LOG"; then echo "PASS $1"; else echo "FAIL $1"; grep -E "Error|violated|Temporal|cursor|event" "$LOG" | head -8; fi
