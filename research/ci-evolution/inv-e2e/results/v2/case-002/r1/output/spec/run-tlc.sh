#!/usr/bin/env bash
# Bounded TLC runner for the incremental update suite.
# usage: run-tlc.sh <id> <kind> <outer-timeout> <module.tla> <config.cfg> [JSON=trace] -- [extra TLC args]
# States live under /dev/shm/specula-e2e-case-002/<id> and are removed after the run.
set -uo pipefail
spec_root=/work/current/.specula-output/spec
log_root="$spec_root/output/update"
state_root=/dev/shm/specula-e2e-case-002
ledger="$log_root/command-results.ndjson"
cp=/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar
id="$1"; kind="$2"; tmo="$3"; module="$4"; cfg="$5"; shift 5
json=""
if [[ "${1:-}" == JSON=* ]]; then json="${1#JSON=}"; shift; fi
[[ "${1:-}" == "--" ]] && shift
extra=("$@")
mkdir -p "$log_root" "$state_root"
meta="$state_root/$id"
rm -rf "$meta"; mkdir -p "$meta"
log="$log_root/$id.log"
heap="${TLC_HEAP:-24g}"
cmd=(timeout "$tmo" env "JSON=$json" java -XX:+UseParallelGC -Xmx"$heap" -cp "$cp" tlc2.TLC -cleanup -metadir "$meta" -config "$cfg" "${extra[@]}" "$module")
printf 'COMMAND: cd %q &&' "$spec_root" > "$log"; printf ' %q' "${cmd[@]}" >> "$log"; printf '\n' >> "$log"
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
( cd "$spec_root" && "${cmd[@]}" ) >> "$log" 2>&1
rc=$?
finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)
rm -rf "$meta"
completed=false; grep -q 'Model checking completed. No error has been found.' "$log" && completed=true
violation=false; grep -qE 'is violated|Temporal properties were violated|Action property .* violated' "$log" && violation=true
errors=false; grep -qE '^Error:|Exception|OutOfMemoryError' "$log" && errors=true
queue=$(grep -oE '[0-9]+ states left on queue' "$log" | tail -1 | grep -oE '^[0-9]+' || echo "")
depth=$(grep -oE 'depth of the complete state graph search is [0-9]+' "$log" | tail -1 | grep -oE '[0-9]+$' || echo "")
distinct=$(grep -oE '[0-9]+ distinct states found' "$log" | tail -1 | grep -oE '^[0-9]+' || echo "")
jq -cn --arg id "$id" --arg kind "$kind" --arg log "spec/output/update/$id.log" --arg json "$json" \
   --arg started "$started" --arg finished "$finished" --argjson rc "$rc" \
   --argjson completed "$completed" --argjson violation "$violation" --argjson errors "$errors" \
   --arg queue "$queue" --arg depth "$depth" --arg distinct "$distinct" \
   '{id:$id,kind:$kind,log:$log,trace:$json,started:$started,finished:$finished,exit_code:$rc,completed_no_error:$completed,violation_reported:$violation,error_text:$errors,states_left_on_queue:$queue,depth:$depth,distinct_states:$distinct}' >> "$ledger"
echo "$id rc=$rc completed=$completed violation=$violation errors=$errors queue=$queue depth=$depth distinct=$distinct"
exit 0
