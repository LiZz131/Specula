#!/usr/bin/env bash
# Usage: run-trace-validation.sh <label> <cfg> <trace.ndjson>...
# Runs real TLC trace validation for each trace, one log per trace under
# spec/output/trace/, appends a ledger line, and removes the TLC state dir.
set -uo pipefail
spec_root=/work/current/.specula-output/spec
label="$1"; cfg="$2"; shift 2
cp=/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar
log_dir="$spec_root/output/trace"; mkdir -p "$log_dir"
ledger="$spec_root/output/trace/ledger.ndjson"
rc=0
for t in "$@"; do
  name=$(basename "$t" .ndjson)
  id="$label-$name"
  meta=/dev/shm/specula-e2e-case-002/trace-$id-$$
  mkdir -p "$meta"
  log="$log_dir/$id.log"
  cmd="cd $spec_root && JSON=$t timeout 900s java -Xmx8g -cp $cp tlc2.TLC -config $cfg -metadir $meta -workers 1 -noGenerateSpecTE Trace.tla"
  echo "COMMAND: $cmd" > "$log"
  start=$(date -u +%FT%TZ)
  (cd "$spec_root" && JSON="$t" timeout 900s java -Xmx8g -cp "$cp" tlc2.TLC -config "$cfg" -metadir "$meta" -workers 1 -noGenerateSpecTE Trace.tla) >> "$log" 2>&1
  ec=$?
  rm -rf "$meta"
  records=$(grep -c '"tag":"trace"' "$t")
  ok=false; grep -q "Model checking completed. No error has been found." "$log" && ok=true
  echo "{\"id\":\"$id\",\"cfg\":\"$cfg\",\"trace\":\"$t\",\"records\":$records,\"exit\":$ec,\"no_error\":$ok,\"started\":\"$start\",\"log\":\"spec/output/trace/$id.log\"}" >> "$ledger"
  printf '%-60s exit=%s no_error=%s records=%s\n' "$id" "$ec" "$ok" "$records"
  [[ $ok == true ]] || rc=1
done
exit $rc
