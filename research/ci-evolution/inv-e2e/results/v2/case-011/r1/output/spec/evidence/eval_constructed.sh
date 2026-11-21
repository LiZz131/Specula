#!/usr/bin/env bash
# usage: eval_constructed.sh <suite_root> <id> <Case>
set -uo pipefail
root="$1"; id="$2"; case_name="$3"
dir="$root/spec/evidence/$id"; mkdir -p "$dir"
cat > "$dir/EvidenceConstructed.cfg" <<CFG
SPECIFICATION EvSpec
CONSTANTS
    Server <- ReferenceServer
    NodeOrder <- ReferenceNodeOrder
    InitialConfig <- ReferenceInitialConfig
    MaxTerm = 3
    MaxLogIndex = 6
    TickPreVoteModes <- ReferenceTickPreVoteModes
    PreVoteFallbackPeers <- ReferencePreVoteFallbackPeers
    Case = "$case_name"
INVARIANTS
    ReportInv
PROPERTIES
    ReportStep
CFG
state="/dev/shm/specula-e2e-case-011/evidence-$id-$$"; mkdir -p "$state"
cd "$root/spec/evidence"
echo "# command: java -DTLA-Library=$root/spec tlc2.TLC -workers 1 -deadlock -config $dir/EvidenceConstructed.cfg EvidenceConstructed" > "$dir/tlc.log"
timeout 5m java -DTLA-Library="$root/spec" -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar \
  tlc2.TLC -workers 1 -deadlock -metadir "$state" -config "$dir/EvidenceConstructed.cfg" EvidenceConstructed >> "$dir/tlc.log" 2>&1
echo "# rc=$?" >> "$dir/tlc.log"; rm -rf "$state"
grep -E '^<<"CONSTRUCTED|Error|Model checking completed' "$dir/tlc.log" | sort -u
