#!/usr/bin/env bash
# Bounded TLC campaign runner.  Usage:
#   run-tlc.sh <label> <spec.tla> <cfg> <bfs|sim> <minutes> <workers> <heapGB> [simDepth]
# States live under /dev/shm/specular-e2e-case-002/<label> and are removed
# after the run; logs go to spec/output/mc/<label>.log; a JSON summary line is
# appended to spec/output/mc/campaigns.ndjson.
set -uo pipefail
cd /work/current/.specular-output/spec
label=$1; spec=$2; cfg=$3; mode=$4; minutes=$5; workers=$6; heap=$7; depth=${8:-100}
log=output/mc/$label.log
meta=/dev/shm/specular-e2e-case-002/$label
mkdir -p "$meta"
secs=$((minutes*60))
extra=""
if [[ $mode == sim ]]; then extra="-simulate num=999999999 -depth $depth"; fi
cmd="timeout $((secs+600))s java -Xmx${heap}g -XX:+UseParallelGC -Dtlc2.TLC.stopAfter=$secs -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -workers $workers -cleanup -metadir $meta -config $cfg $extra $spec"
start=$(date -u +%FT%TZ)
bash -c "$cmd" > "$log" 2>&1
rc=$?
rm -rf "$meta"
end=$(date -u +%FT%TZ)
viol=$(grep -m1 -oE "Invariant [A-Za-z_]+ is violated|Temporal property [A-Za-z_]+ was violated|Action property [A-Za-z_]+ is violated|Error: [^.]*deadlock[^.]*" "$log" | head -1)
stats=$(grep -E "states generated" "$log" | tail -1)
depthl=$(grep -oE "depth of the complete state graph search is [0-9]+" "$log" | tail -1)
done_=$(grep -c "Model checking completed" "$log")
python3 -I -c "
import json,sys
print(json.dumps(dict(label=sys.argv[1],spec=sys.argv[2],cfg=sys.argv[3],mode=sys.argv[4],budget_minutes=int(sys.argv[5]),workers=int(sys.argv[6]),command='cd spec && '+sys.argv[7],log='spec/'+sys.argv[8],started_at_utc=sys.argv[9],finished_at_utc=sys.argv[10],exit_code=int(sys.argv[11]),violation=sys.argv[12],last_stats=sys.argv[13],depth=sys.argv[14],completed_naturally=sys.argv[15]=='1')))
" "$label" "$spec" "$cfg" "$mode" "$minutes" "$workers" "$cmd" "$log" "$start" "$end" "$rc" "$viol" "$stats" "$depthl" "$done_" | tee -a output/mc/campaigns.ndjson
