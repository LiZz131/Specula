#!/usr/bin/env bash
# Negative controls: each mutant flips one recorded field that Trace.tla must
# consume; TLC is expected to REJECT every mutant (non-vacuity evidence).
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
t="$suite_root/traces"; m="$t/mutants"; mkdir -p "$m"
mut() { # name source line jq-filter
    local name="$1" src="$2" line="$3" filter="$4"
    python3 -I - "$t/$src.ndjson" "$m/$name.ndjson" "$line" "$filter" <<'PY'
import json,sys
src,dst,line,expr=sys.argv[1],sys.argv[2],int(sys.argv[3]),sys.argv[4]
rows=[json.loads(l) for l in open(src)]
path,val=expr.split('=',1)
obj=rows[line-1]['event']
keys=path.split('.')
for k in keys[:-1]: obj=obj[k]
obj[keys[-1]]=json.loads(val)
with open(dst,'w') as f:
    for r in rows: f.write(json.dumps(r,sort_keys=True)+"\n")
PY
}
mut M1_establish_clears_precandidate candidate_pre_vote_then_leader 4 'post.pre_candidate_active=false'
mut M2_prevote_elect_drops_leader candidate_pre_vote_then_leader 5 'post.leader_active=false'
mut M3_prevote_req_reject_flip pre_vote_req_grant 1 'args.response_granted=false'
mut M4_pre_elect_bumps_term pre_elect_multi 1 'post.vote={"term":2,"node":"1","committed":false}'
mut M5_no_greater_log pre_vote_resp_reject_greater_log 2 'post.seen_greater_log=false'
mut M6_append_keeps_precandidate pre_vote_superseded_by_append 2 'post.pre_candidate_active=true'
mut M7_prevote_resp_vote_changed pre_vote_req_reject_lease 1 'args.response_vote={"term":1,"node":"2","committed":false}'
mut M8_stale_round_vote pre_vote_resp_quorum 2 'args.candidate_vote={"term":1,"node":"1","committed":false}'
mut M9_pre_state_mismatch candidate_pre_vote_then_leader 3 'pre.candidate_active=false'
mut M10_prevote_req_mutates pre_vote_req_grant 1 'post.vote={"term":2,"node":"2","committed":false}'
mut M11_no_send_pre_vote pre_elect_multi 1 'post.send_pre_vote_pending=false'
cd "$suite_root/spec"
state="/dev/shm/specula-e2e-case-011/mutants-$$"; trap 'rm -rf "$state"' EXIT; mkdir -p "$state"
out="output/v1-trace-mutation-controls.txt"; : > "$out"
for f in "$m"/*.ndjson; do
    n="$(basename "$f" .ndjson)"; log="output/v1-trace-mutant-$n.log"
    timeout 5m env SPECULA_TRACE="$f" java -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar \
        tlc2.TLC -workers 1 -cleanup -metadir "$state/$n" -config Trace.cfg Trace > "$log" 2>&1
    rm -rf "$state/$n"
    if grep -q 'Model checking completed. No error has been found.' "$log"; then
        echo "UNEXPECTED-ACCEPT $n" | tee -a "$out"
    else
        echo "REJECTED $n: $(grep -E 'Temporal properties were violated|Deadlock|Error:' "$log" | head -1)" | tee -a "$out"
    fi
done
