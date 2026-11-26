#!/usr/bin/env bash
# Negative controls: each mutated copy of a fresh trace changes one captured
# field; Trace.tla must REJECT it (TLC error / TraceConsumed violation).
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mdir="$suite_root/spec/evidence/trace-mutations"
state_root="/dev/shm/specular-e2e-case-011/mutation-$$"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
trap 'rm -rf "$state_root"' EXIT INT TERM
mkdir -p "$mdir" "$state_root"
# name|source trace|line (1-based)|jq filter applied to that line
muts=(
 "M1_pre_elect_bumps_term|pre_elect_multi|1|.event.post.vote.term += 1"
 "M2_pre_elect_wrong_req_log|pre_elect_multi|1|.event.post.send_pre_vote_req.last_log.index += 1"
 "M3_pre_elect_no_round|pre_elect_multi|1|.event.post.pre_candidate_active = false"
 "M4_pre_vote_req_changes_vote|pre_vote_req_grant|1|.event.post.vote.term += 1"
 "M5_pre_vote_req_flip_grant|pre_vote_req_grant|1|.event.args.response_granted = false"
 "M6_lease_reject_flip_grant|pre_vote_req_lease_reject|1|.event.args.response_granted = true"
 "M7_quorum_keeps_round|pre_vote_resp_quorum|2|.event.post.pre_candidate_active = true"
 "M8_reject_no_greater_log|pre_vote_resp_reject_greater_log|2|.event.post.seen_greater_log = false"
 "M9_establish_clears_round|stale_pre_vote_after_leader|4|.event.post.pre_candidate_active = false"
 "M10_stale_round_ignored|stale_pre_vote_after_leader|5|.event.post.role = \"Leader\" | .event.post.vote = {\"term\":2,\"node\":\"1\",\"committed\":true}"
 "M11_cleared_round_survives|pre_vote_cleared_by_vote_request|2|.event.post.pre_candidate_active = true"
 "M12_pre_grants_wrong|pre_vote_resp_reject_greater_log|1|.event.post.pre_grants = [\"1\",\"2\"]"
)
cd "$suite_root/spec"
ok=0
for m in "${muts[@]}"; do
  IFS='|' read -r name src line filter <<< "$m"
  out="$mdir/$name.ndjson"
  awk -v L="$line" 'NR==L' "$suite_root/traces/$src.ndjson" | jq -c "$filter" > /tmp/mut_line.json
  awk -v L="$line" 'NR!=L {print; next} {while ((getline x < "/tmp/mut_line.json") > 0) print x}' "$suite_root/traces/$src.ndjson" > "$out"
  log="$mdir/$name.log"
  timeout 5m env SPECULAR_TRACE="$out" java -cp "$classpath" tlc2.TLC -workers 1 \
      -metadir "$state_root/$name" -config Trace.cfg Trace > "$log" 2>&1
  if grep -q 'Model checking completed. No error has been found.' "$log"; then
     echo "CONTROL-FAILED (accepted) $name"; ok=1
  else
     echo "REJECTED $name ($(grep -m1 -o 'Deadlock reached\|Temporal properties were violated\|Invariant [A-Za-z]* is violated' "$log"))"
  fi
done
exit $ok
