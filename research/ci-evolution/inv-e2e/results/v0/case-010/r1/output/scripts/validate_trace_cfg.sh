#!/usr/bin/env bash
# Usage: validate_trace_cfg.sh <trace-path> <cfg> <logname>
set -uo pipefail
JSON=$1 /work/current/.specula-output/scripts/tlc.sh Trace "$2" "$3" 20m -workers 1
LOG=/work/current/.specula-output/spec/output/$3.log
if grep -q "No error has been found" "$LOG"; then echo "ACCEPTED $1"; else M=$(grep -o "cursor = [0-9]*" "$LOG" | awk '{print $3}' | sort -n | tail -1); echo "REJECTED $1 (max cursor reached: $M)"; fi
