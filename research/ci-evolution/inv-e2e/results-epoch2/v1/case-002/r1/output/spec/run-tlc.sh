#!/usr/bin/env bash
# Usage: run-tlc.sh ID MODULE CFG TIMEOUT_S [extra TLC args...]
# Env: JSON=<trace path> for trace validation; WORKERS (default 8); HEAP (default 8g)
# States: /dev/shm/specula-e2e-case-002/<ID> (removed after the run)
# Logs:   spec/output/incremental/runs/<ID>.log ; ledger: spec/output/incremental/runs/ledger.ndjson
set -uo pipefail
id="$1"; module="$2"; cfg="$3"; budget="$4"; shift 4
spec_root=/work/current/.specula-output/spec
log_root="$spec_root/output/incremental/runs"
meta="/dev/shm/specula-e2e-case-002/$id"
cp_jars=/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar
mkdir -p "$log_root" "$meta"
log="$log_root/$id.log"
cmd=(timeout "$budget" java ${STOP_AFTER:+-Dtlc2.TLC.stopAfter=$STOP_AFTER} -Djava.io.tmpdir="$meta" -XX:+UseParallelGC -Xmx${HEAP:-8g} -cp "$cp_jars" tlc2.TLC -noGenerateSpecTE -workers "${WORKERS:-8}" -metadir "$meta" -config "$cfg" "$@" "$module")
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
{ echo "COMMAND: cd $spec_root && ${JSON:+JSON=$JSON }${cmd[*]}"; echo "STARTED: $started"; } > "$log"
( cd "$spec_root"; if [[ -n "${JSON:-}" ]]; then JSON="$JSON" "${cmd[@]}"; else "${cmd[@]}"; fi ) >> "$log" 2>&1
rc=$?
finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "EXIT: $rc FINISHED: $finished" >> "$log"
rm -rf "$meta"
outcome=other
grep -q "Model checking completed. No error has been found." "$log" && outcome=no-error
grep -qE "Invariant .* is violated|Temporal properties were violated|Action property .* is violated|is violated" "$log" && outcome=violation
grep -qE "^Error: TLC threw|Exception|Error: Parsing|Semantic errors" "$log" && [[ $outcome == other ]] && outcome=error
[[ $rc -eq 124 ]] && outcome="timeout-$outcome"
states=$(grep -E "states generated" "$log" | tail -1)
depth=$(grep -E "depth of the complete state graph|The depth" "$log" | tail -1)
jq -cn --arg id "$id" --arg mod "$module" --arg cfg "$cfg" --arg json "${JSON:-}" --arg started "$started" --arg finished "$finished" --argjson rc "$rc" --arg outcome "$outcome" --arg states "$states" --arg depth "$depth" --arg log "spec/output/incremental/runs/$id.log" \
  '{id:$id,module:$mod,cfg:$cfg,trace:$json,started:$started,finished:$finished,exit:$rc,outcome:$outcome,states:$states,depth:$depth,log:$log}' >> "$log_root/ledger.ndjson"
echo "$id rc=$rc outcome=$outcome | $states | $depth"
