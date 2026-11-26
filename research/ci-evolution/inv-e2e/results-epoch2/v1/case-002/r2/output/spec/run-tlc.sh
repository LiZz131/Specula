#!/usr/bin/env bash
# Bounded TLC runner for the incremental campaign.
# usage: run-tlc.sh <run-id> <spec.tla> <cfg> <outer-timeout-seconds> [extra TLC args...]
# - TLC states live under /dev/shm/specular-e2e-case-002/<run-id>-<pid> and are removed afterwards.
# - Log: spec/output/incr/<run-id>.log ; command/outcome appended to spec/output/incr/command-results.ndjson
set -uo pipefail
id="$1"; spec="$2"; cfg="$3"; tmo="$4"; shift 4
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
out="$here/output/incr"; mkdir -p "$out"
meta="/dev/shm/specular-e2e-case-002/${id}-$$"; mkdir -p "$meta"
log="$out/$id.log"
cmd=(timeout "${tmo}s" java -XX:+UseParallelGC -Xmx24g -Dtlc2.tool.fp.FPSet.impl=tlc2.tool.fp.OffHeapDiskFPSet
     -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC
     -config "$cfg" -metadir "$meta" -cleanup "$@" "$spec")
start=$(date -u +%FT%TZ)
"${cmd[@]}" > "$log" 2>&1
rc=$?
end=$(date -u +%FT%TZ)
rm -rf "$meta"
python3 - "$out/command-results.ndjson" "$id" "$rc" "$start" "$end" "$log" "${cmd[*]}" <<'PY'
import json,sys,re
p,i,rc,s,e,log,cmd=sys.argv[1:]
t=open(log,errors='replace').read()
def last(rx):
    m=re.findall(rx,t); return m[-1] if m else None
rec={"id":i,"exit_code":int(rc),"started_utc":s,"finished_utc":e,"log":log.split('.specular-output/')[-1],
     "command":"cd spec && "+cmd,
     "violation":bool(re.search(r"is violated|Error: (Invariant|Action property|Temporal)",t)),
     "completed":"Model checking completed. No error has been found." in t,
     "distinct_states":last(r"(\d[\d,]*) distinct states found"),
     "states_left":last(r"(\d[\d,]*) states left on queue"),
     "depth":last(r"depth of the complete state graph search is (\d+)")}
open(p,'a').write(json.dumps(rec)+"\n"); print(json.dumps(rec))
PY
exit $rc
