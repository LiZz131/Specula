#!/usr/bin/env bash
# Runs the remaining campaigns with at most $MAXJ concurrent TLC jobs.
cd "$(dirname "${BASH_SOURCE[0]}")"
out=../spec/output
until grep -q '^EXIT:' $out/mc-${WAIT_FOR:-std-MC}.log; do sleep 10; done
MAXJ=${MAXJ:-3}
jobs_list=(
"Update|Update_focused_filtered.cfg|update-focused-filtered|30|8|-coverage 10"
"Update|Update_open_filtered.cfg|update-open-filtered|30|8|-coverage 10"
"Update|Update_discharge.cfg|update-discharge|30|6|-coverage 10"
"Update|MC_hunt_prevote_stale_round_filtered.cfg|hunt-prevote_stale_round-filtered-bfs|30|6|-coverage 10"
"Update|MC_hunt_prevote_membership_filtered.cfg|hunt-prevote_membership-filtered-bfs|30|6|-coverage 10"
"Update|MC_hunt_prevote_default_rpc_filtered.cfg|hunt-prevote_default_rpc-filtered-bfs|30|6|-coverage 10"
"Update|MC_hunt_prevote_single_voter_filtered.cfg|hunt-prevote_single_voter-filtered-bfs|30|6|-coverage 10"
"Update|MC_hunt_prevote_stale_round_filtered.cfg|hunt-prevote_stale_round-filtered-sim|15|8|-simulate num=999999999 -depth 60"
"Update|MC_hunt_prevote_membership_filtered.cfg|hunt-prevote_membership-filtered-sim|15|8|-simulate num=999999999 -depth 60"
"Update|MC_hunt_prevote_default_rpc_filtered.cfg|hunt-prevote_default_rpc-filtered-sim|15|8|-simulate num=999999999 -depth 60"
"Update|MC_hunt_prevote_single_voter_filtered.cfg|hunt-prevote_single_voter-filtered-sim|15|8|-simulate num=999999999 -depth 60"
"Update|MC_hunt_prevote_leader_object_filtered.cfg|hunt-prevote_leader_object-filtered-sim|15|8|-simulate num=999999999 -depth 60"
"Update|Update_full_filtered.cfg|update-full-filtered-sim|15|8|-simulate num=999999999 -depth 60"
)
for j in "${jobs_list[@]:${SKIP:-0}}"; do
  IFS='|' read -r mod cfg label mins w flags <<< "$j"
  while [ "$(jobs -rp | wc -l)" -ge "$MAXJ" ]; do wait -n; done
  echo "$(date -u +%H:%M:%S) start $label"
  SPECULA_TLC_HEAP=20g ./run-tlc.sh "$mod" "$cfg" "$label" "$mins" "$w" $flags &
done
wait
echo "$(date -u +%H:%M:%S) queue done"
