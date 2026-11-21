#!/usr/bin/env bash
# Field-consumption evidence: mutate one recorded field at a time and require
# TLC trace validation to REJECT the mutated trace. Mutants live in
# traces/mutants/ and are not part of the retained conformance suite.
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
spec_dir="$suite_root/spec"
mdir="$suite_root/traces/mutants"
state_parent="/dev/shm/specula-e2e-case-011"
run_state="$state_parent/mutant-$$"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
out="$spec_dir/output/trace-mutation-check.log"
trap 'rm -rf "$run_state"' EXIT INT TERM
mkdir -p "$mdir" "$run_state"
: > "$out"
# name | source trace | 0-based line | jq mutation
mutants=(
  "m_pre_active|pre_elect_multi|0|.event.post.pre_candidate_active = false"
  "m_pre_vote|pre_elect_multi|0|.event.post.pre_candidate_vote.term = 3"
  "m_pre_grants|pre_elect_multi|0|.event.post.pre_grants = [\"1\",\"2\"]"
  "m_send_pre_vote|pre_elect_multi|0|.event.post.send_pre_vote_pending = false"
  "m_req_vote|pre_elect_multi|0|.event.args.req_vote.term = 1"
  "m_pre_cfg|pre_elect_multi|0|.event.post.pre_candidate_config = [[\"1\",\"2\"]]"
  "m_single_role|pre_elect_single|0|.event.post.role = \"Follower\""
  "m_prevreq_granted|pre_vote_req_grant|0|.event.args.response_granted = false"
  "m_prevreq_vote_change|pre_vote_req_grant|0|.event.post.vote.term = 2"
  "m_prevreq_lease|pre_vote_req_reject_lease|0|.event.args.response_granted = true"
  "m_prevreq_log|pre_vote_req_reject_log|0|.event.args.response_granted = true"
  "m_prevreq_order|pre_vote_req_reject_vote|0|.event.args.response_granted = true"
  "m_prevreq_resp_log|pre_vote_req_grant|0|.event.args.response_last_log.index = 0"
  "m_prevresp_noelect|pre_vote_resp_quorum_elect|2|.event.post.candidate_active = false"
  "m_prevresp_greater|pre_vote_resp_reject_greater_log|2|.event.post.seen_greater_log = false"
  "m_prevresp_joint|pre_vote_resp_joint_no_quorum|2|.event.post.pre_grants = [\"1\"]"
  "m_stale_keep_pre|stale_pre_vote_after_establish|2|.event.post.pre_candidate_active = false"
  "m_stale_leader|stale_pre_vote_after_establish|4|.event.post.leader_active = false"
  "m_stale_vote|stale_pre_vote_after_establish|4|.event.post.vote.term = 2"
  "m_stale_drain|stale_pre_vote_after_establish|3|.event.args.commands = [\"RebuildReplicationStreams\"]"
  "m_hb_cancel|heartbeat_cancels_pre_vote|2|.event.post.pre_candidate_active = true"
  "m_hb_lease|heartbeat_cancels_pre_vote|2|.event.post.lease_valid = false"
  "m_grant_cancel|vote_grant_cancels_pre_vote|2|.event.post.pre_candidate_active = true"
  "m_pre_state|stale_pre_vote_after_establish|2|.event.pre.role = \"Follower\""
  "m_establish_lease|establish_leader|0|.event.post.lease_valid = false"
)
fail=0
cd "$spec_dir"
for spec in "${mutants[@]}"; do
  IFS='|' read -r name src line expr <<< "$spec"
  python3 -I - "$suite_root/traces/$src.ndjson" "$mdir/$name.ndjson" "$line" "$expr" <<'PY'
import json, subprocess, sys
src, dst, line, expr = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
lines = open(src).read().splitlines()
lines[line] = subprocess.run(["jq", "-c", expr], input=lines[line], capture_output=True, text=True, check=True).stdout.strip()
open(dst, "w").write("\n".join(lines) + "\n")
PY
  log="$spec_dir/output/mutant-$name.log"
  timeout 3m env SPECULA_TRACE="$mdir/$name.ndjson" java -XX:+UseParallelGC -cp "$classpath" tlc2.TLC \
      -workers 1 -cleanup -metadir "$run_state/$name" -config Trace.cfg Trace > "$log" 2>&1
  rm -rf "$run_state/$name"
  if grep -q 'Model checking completed. No error has been found.' "$log"; then
    echo "NOT-REJECTED $name ($src line $line: $expr)" | tee -a "$out"; fail=1
  else
    reason=$(grep -m1 -E 'Temporal properties were violated|Deadlock reached|Invariant .* is violated|Error:' "$log")
    echo "REJECTED $name ($src line $line: $expr) -> $reason" | tee -a "$out"
  fi
done
rm -f "$spec_dir"/Trace_TTrace_*.tla
exit $fail
