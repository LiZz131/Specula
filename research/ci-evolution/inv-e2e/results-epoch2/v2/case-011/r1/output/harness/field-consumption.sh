#!/usr/bin/env bash
# Negative control for trace-field consumption: each mutant changes exactly
# one captured field of one event of a fresh trace; Trace.tla must REJECT it.
# Mutants are written under spec/output/field-consumption/ (never under traces/).
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$suite_root/spec/output/field-consumption"; mkdir -p "$out"
spec_dir="$suite_root/spec"; classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
# name|trace|event(1-based)|jq path|jq value
mutants=(
"m01|prevote_start|1|.event.post.pre_candidate_active|false"
"m02|prevote_start|1|.event.post.pre_grants|[]"
"m03|prevote_start|1|.event.post.pre_candidate_vote.term|3"
"m04|prevote_start|1|.event.post.send_pre_vote_pending|false"
"m05|prevote_start|1|.event.args.req_last_log.index|0"
"m06|prevote_start|1|.event.post.vote.term|2"
"m07|prevote_req_grant|1|.event.args.response_granted|false"
"m08|prevote_req_grant|1|.event.post.lease_valid|true"
"m09|prevote_resp_reject_greater_log|2|.event.post.seen_greater_log|false"
"m10|stale_prevote_after_win|4|.event.post.pre_candidate_active|false"
"m11|stale_prevote_after_win|5|.event.post.role|\"Leader\""
"m12|prevote_joint_grant_then_elect|1|.event.post.pre_candidate_config|[[\"1\",\"2\",\"3\"]]"
"m13|prevote_cleared_by_heartbeat|2|.event.post.pre_candidate_active|true"
"m14|stale_prevote_after_win|4|.event.post.lease_valid|false"
"m15|prevote_resp_quorum_elect|2|.event.args.candidate_vote.term|3"
"m16|prevote_tick_start|1|.event.post.seen_greater_log|true"
"m17|stale_prevote_after_win|5|.event.pre.pre_grants|[\"1\",\"3\"]"
"m18|prevote_joint_grant_then_elect|2|.event.post.pre_grants|[\"1\"]"
"m19|prevote_req_reject_lease|1|.event.args.response_granted|true"
"m20|prevote_cleared_by_higher_vote_resp|4|.event.post.pre_candidate_active|true"
)
run_one() {
  IFS='|' read -r name trace ev path val <<< "$1"
  local src="$suite_root/traces/$trace.ndjson" dst="$out/$name-$trace.ndjson"
  rm -f "$dst"
  python3 -I -c '
import json,sys
src,dst,ev,path,val=sys.argv[1:]
lines=open(src).read().splitlines()
rec=json.loads(lines[int(ev)-1])
keys=path.strip(".").split(".")
o=rec
for k in keys[:-1]: o=o[k]
o[keys[-1]]=json.loads(val)
lines[int(ev)-1]=json.dumps(rec)
open(dst,"w").write("\n".join(lines)+"\n")' "$src" "$dst" "$ev" "$path" "$val"
  local meta="/dev/shm/specula-e2e-case-011/fc-$name-$$" log="$out/$name-$trace.log"
  ( cd "$spec_dir" && timeout 3m env SPECULA_TRACE="$dst" java -cp "$classpath" tlc2.TLC -workers 1 -noGenerateSpecTE \
      -metadir "$meta" -config Trace.cfg Trace > "$log" 2>&1 ); rm -rf "$meta"
  if [ ! -s "$dst" ]; then echo "MUTANT-NOT-BUILT $name"; return; fi
  if grep -q 'Model checking completed. No error has been found.' "$log"; then
     echo "NOT-CONSUMED $name $trace ev$ev $path=$val"
  else echo "REJECTED $name $trace ev$ev $path=$val ($(grep -oE 'Deadlock reached|Temporal properties were violated|Invariant [A-Za-z]+ is violated' "$log" | head -1))"; fi
}
rm -f "$out"/*.ndjson "$out"/*.log
for m in "${mutants[@]}"; do run_one "$m" > "$out/.res-${m%%|*}" & 
  while [ "$(jobs -rp | wc -l)" -ge 8 ]; do wait -n; done; done; wait
cat "$out"/.res-* | sort; rm -f "$out"/.res-*
