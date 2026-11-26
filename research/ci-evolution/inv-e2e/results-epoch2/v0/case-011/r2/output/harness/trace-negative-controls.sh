#!/usr/bin/env bash
# Mutate one field of a fresh trace and require Trace.tla to REJECT it. Shows
# that the update fields are consumed by active Trace predicates.
set -euo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$suite_root/spec/output/negative-controls"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
state="/dev/shm/specular-e2e-case-011/negctl-$$"
trap 'rm -rf "$state"' EXIT INT TERM
mkdir -p "$out" "$state"
# name|trace|line|jq mutation
controls=(
 "precand_active|pre_elect_follower|1|.event.post.pre_candidate_active=false"
 "precand_vote|pre_elect_follower|1|.event.post.pre_candidate_vote.term=1"
 "sendprevote_lastlog|pre_elect_follower|1|.event.post.send_pre_vote_req.last_log.index=0"
 "prevote_granted|pre_vote_req_grant|1|.event.args.response_granted=false"
 "prevote_lease|pre_vote_req_reject_lease|1|.event.args.response_granted=true"
 "prevote_resp_vote|pre_vote_req_grant|1|.event.args.response_vote.term=2"
 "prevote_no_side_effect|pre_vote_req_grant|1|.event.post.vote.term=2"
 "greater_log|pre_vote_resp_reject_greater_log|3|.event.post.seen_greater_log=false"
 "gate_forwarded|pre_vote_resp_stale_ignored|3|.event.args.forwarded=true"
 "leader_retained|candidate_prevote_then_leader|8|.event.post.leader_active=false"
 "leader_vote|candidate_prevote_then_leader|8|.event.post.leader_vote.term=3"
 "precand_survives_establish|candidate_prevote_then_leader|6|.event.post.pre_candidate_active=false"
 "single_voter_elect|pre_elect_single_voter|1|.event.post.candidate_active=false"
 "cleared_by_follow|pre_vote_cleared_by_vote_grant|3|.event.post.pre_candidate_active=true"
)
: > "$out/summary.tsv"
for c in "${controls[@]}"; do
  IFS='|' read -r name trace line mut <<< "$c"
  src="$suite_root/traces/$trace.ndjson"; dst="$out/$name.ndjson"
  awk -v L="$line" -v M="$mut" 'NR==L{cmd="jq -c '\''" M "'\''"; print | cmd; close(cmd); next} {print}' "$src" > "$dst"
  # sanity: exactly one line differs
  diffs=$(diff <(jq -cS . "$src") <(jq -cS . "$dst") | grep -c '^<' || true)
  set +e
  (cd "$suite_root/spec" && timeout 3m env SPECULAR_TRACE="$dst" java -XX:+UseParallelGC -cp "$classpath" tlc2.TLC -workers 1 \
     -metadir "$state/$name" -config Trace.cfg Trace > "$out/$name.log" 2>&1)
  set -e
  rm -rf "$state/$name"
  if grep -q 'No error has been found' "$out/$name.log"; then res=ACCEPTED_BAD; else res=REJECTED; fi
  printf '%s\t%s\t%s:%s\tchanged_lines=%s\t%s\n' "$name" "$res" "$trace" "$line" "$diffs" "$mut" | tee -a "$out/summary.tsv"
done
