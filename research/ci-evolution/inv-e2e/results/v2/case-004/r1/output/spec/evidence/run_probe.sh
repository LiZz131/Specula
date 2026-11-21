#!/usr/bin/env bash
# usage: run_probe.sh <trace.ndjson> <evidence-id>   -> spec/evidence/<id>/tlc.log
set -uo pipefail
ev="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
spec="$(cd "$ev/.." && pwd)"
t="$(readlink -f "$1")"; id="$2"
mkdir -p "$ev/$id"
meta=/dev/shm/specula-e2e-case-004/evidence-$id-$$
( cd "$ev" && JSON="$t" timeout 10m java -DTLA-Library="$spec" -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar \
    tlc2.TLC -noGenerateSpecTE -deadlock -workers 1 -metadir "$meta" -config EvidenceProbe.cfg EvidenceProbe.tla ) > "$ev/$id/tlc.log" 2>&1
rc=$?; rm -rf "$meta"
echo "trace=$1 rc=$rc" > "$ev/$id/source.txt"
grep -E '^<<' "$ev/$id/tlc.log" | sort -u
grep -E "Model checking completed|Error" "$ev/$id/tlc.log" | head -3
