#!/usr/bin/env bash
# Usage: trace-one.sh <scenario> [cfg] [tag]   -- real TLC trace validation of traces/<scenario>.ndjson
set -u
sc="$1"; cfg="${2:-Trace.cfg}"; tag="${3:-trace}"
here="$(cd "$(dirname "$0")" && pwd)"
export JSON="$here/../traces/$sc.ndjson"
TLC_HEAP=8g "$here/tlc.sh" "$tag-$sc" Trace.tla "$cfg" 1800s -workers 1 -deadlock
rc=$?
log="$here/output/$tag-$sc.log"
if grep -q "Model checking completed. No error has been found" "$log"; then echo "$sc: PASS (rc=$rc)"; else echo "$sc: FAIL (rc=$rc)"; fi
exit $rc
