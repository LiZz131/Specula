#!/usr/bin/env bash
# usage: eval_trace_evidence.sh <suite_root> <id> <trace-case> <event>
set -uo pipefail
root="$1"; id="$2"; case_name="$3"; ev="$4"
dir="$root/spec/evidence/$id"; mkdir -p "$dir"
sed "s/EvidenceEvent = 1/EvidenceEvent = $ev/" "$root/spec/evidence/EvidenceTrace.cfg" > "$dir/EvidenceTrace.cfg"
state="/dev/shm/specula-e2e-case-011/evidence-$id-$$"
mkdir -p "$state"
cd "$root/spec/evidence"
cmd="SPECULA_TRACE=$root/traces/$case_name.ndjson java -DTLA-Library=$root/spec -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -workers 1 -metadir $state -config $dir/EvidenceTrace.cfg EvidenceTrace"
echo "# command: $cmd" > "$dir/tlc.log"
timeout 5m env SPECULA_TRACE="$root/traces/$case_name.ndjson" java -DTLA-Library="$root/spec" \
  -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -workers 1 \
  -metadir "$state" -config "$dir/EvidenceTrace.cfg" EvidenceTrace >> "$dir/tlc.log" 2>&1
rc=$?
rm -rf "$state"
echo "# rc=$rc" >> "$dir/tlc.log"
grep -E '^<<"(STATE|STEP)"|Model checking completed|Error' "$dir/tlc.log"
