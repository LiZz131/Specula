#!/usr/bin/env bash
# Usage: run-tlc.sh <id> <kind> <timeout> <workers> <module> <config> [json-trace] [extra TLC args...]
# Runs TLC with an outer timeout, metadir under /dev/shm/specula-e2e-case-002,
# log under spec/output/<id>.log, and appends a ledger record.
set -uo pipefail
spec_root=/work/current/.specula-output/spec
log_root="$spec_root/output"
meta_root=/dev/shm/specula-e2e-case-002
ledger="$log_root/command-results.ndjson"
cp=/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar
id="$1"; kind="$2"; to="$3"; workers="$4"; module="$5"; config="$6"; json="${7:-}"; shift 7 || shift $#
extra=("$@")
mkdir -p "$log_root" "$meta_root"
meta="$meta_root/$id.$$"
mkdir -p "$meta"
log="$log_root/$id.log"
heap="${TLC_HEAP:--Xmx24g}"
if [[ -n "$json" ]]; then
  cmd=(timeout "$to" env "JSON=$json" java "$heap" ${JAVA_EXTRA:-} -XX:+UseParallelGC -cp "$cp" tlc2.TLC -cleanup -workers "$workers" -config "$config" -metadir "$meta" "${extra[@]}" "$module")
else
  cmd=(timeout "$to" java "$heap" ${JAVA_EXTRA:-} -XX:+UseParallelGC -cp "$cp" tlc2.TLC -cleanup -workers "$workers" -config "$config" -metadir "$meta" "${extra[@]}" "$module")
fi
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf 'COMMAND: cd %q && %s\n' "$spec_root" "$(printf '%q ' "${cmd[@]}")" > "$log"
( cd "$spec_root" && "${cmd[@]}" ) >> "$log" 2>&1
rc=$?
finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)
rm -rf "$meta"
completed=false; grep -q 'Model checking completed. No error has been found.' "$log" && completed=true
violation=$(grep -m1 -oE 'Invariant [A-Za-z0-9_]+ is violated|Temporal properties were violated|Action property [A-Za-z0-9_]+ is violated|Deadlock reached' "$log" | head -1)
states=$(grep -oE '[0-9,]+ states generated, [0-9,]+ distinct states found, [0-9,]+ states left on queue' "$log" | tail -1)
depth=$(grep -oE 'The depth of the complete state graph search is [0-9]+' "$log" | tail -1 | grep -oE '[0-9]+$')
jq -cn --arg id "$id" --arg kind "$kind" --arg log "spec/output/$id.log" --arg started "$started" --arg finished "$finished" \
   --argjson rc "$rc" --argjson completed "$completed" --arg violation "$violation" --arg states "$states" --arg depth "${depth:-}" \
   --arg config "$config" --arg tlamod "$module" --arg json "$json" \
   '{id:$id,kind:$kind,tla_module:$tlamod,config:$config,trace:$json,exit_code:$rc,natural_completion:$completed,violation:$violation,states:$states,depth:$depth,log:$log,started_at_utc:$started,finished_at_utc:$finished}' >> "$ledger"
echo "$id rc=$rc completed=$completed violation='$violation' states='$states' depth=${depth:-}"
exit 0
