#!/usr/bin/env bash
# Non-vacuity of Trace.tla field checks: each mutant copies one fresh trace,
# changes one captured field on one line, and must be REJECTED by TLC.
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
mut_dir="$spec_dir/output/trace-mutations"
state_parent="/dev/shm/specular-e2e-case-011"
run_state="$state_parent/mut-$$"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
mkdir -p "$mut_dir" "$run_state"
trap 'rm -rf "$run_state"' EXIT INT TERM
summary="$mut_dir/summary.txt"; : > "$summary"
# id|trace|line|jq filter
mutants=(
"m01|prevote_elect_multi|1|.event.post.pre_candidate_active=false"
"m02|prevote_elect_multi|1|.event.post.pre_grants=[]"
"m03|prevote_elect_multi|1|.event.post.pre_candidate_vote.term=3"
"m04|prevote_elect_multi|1|.event.post.pre_candidate_last_log.index=0"
"m05|prevote_elect_multi|2|.event.post.send_pre_vote_pending=true"
"m06|prevote_elect_multi|2|.event.args.targets=[\"2\"]"
"m07|prevote_req_grant|1|.event.args.response_granted=false"
"m08|prevote_req_reject_lease|1|.event.args.response_granted=true"
"m09|prevote_req_reject_log|1|.event.args.response_last_log.index=2"
"m10|prevote_reject_greater_log|3|.event.post.seen_greater_log=false"
"m11|prevote_quorum_elect|3|.event.post.vote.term=1"
"m12|candidate_prevote_establish|9|.event.post.pre_candidate_active=false"
"m13|candidate_prevote_establish|9|.event.post.lease_valid=false"
"m14|candidate_prevote_establish|11|.event.post.leader_active=false"
"m15|prevote_stale_member_panic|10|.event.post.crashed=false"
"m16|prevote_stale_member_panic|9|.event.post.pre_candidate_config=[[\"1\",\"2\",\"3\"]]"
"m17|prevote_cleared_by_vote_request|3|.event.post.pre_candidate_active=true"
"m18|prevote_new_round_same_leader_id|6|.event.post.pre_grants=[\"1\",\"3\"]"
"m19|start_election|1|.event.post.candidate_config=[[\"1\",\"2\"]]"
"m20|establish_leader|1|.event.post.seen_greater_log=true"
)
fail=0
for spec in "${mutants[@]}"; do
  IFS='|' read -r id trace line filter <<< "$spec"
  src="$suite_root/traces/$trace.ndjson"; out="$mut_dir/$id-$trace.ndjson"
  : > "$out"
  ln=0
  while IFS= read -r rec; do
    ln=$((ln+1))
    if [ "$ln" -eq "$line" ]; then echo "$rec" | jq -c "$filter" >> "$out"; else echo "$rec" >> "$out"; fi
  done < "$src"
  log="$mut_dir/$id-$trace.log"
  (cd "$spec_dir" && timeout 5m env SPECULAR_TRACE="$out" java -XX:+UseParallelGC -cp "$classpath" tlc2.TLC \
      -workers 1 -cleanup -metadir "$run_state/$id" -config Trace.cfg Trace > "$log" 2>&1)
  rm -rf "$run_state/$id"
  if grep -q 'Model checking completed. No error has been found.' "$log"; then
    echo "NOT-DETECTED $id $trace line=$line $filter" | tee -a "$summary"; fail=1
  elif grep -qE 'Deadlock reached|Temporal properties were violated|is violated' "$log"; then
    echo "REJECTED $id $trace line=$line $filter" | tee -a "$summary"
  else
    echo "ERROR $id $trace line=$line $filter" | tee -a "$summary"; fail=1
  fi
done
exit $fail
