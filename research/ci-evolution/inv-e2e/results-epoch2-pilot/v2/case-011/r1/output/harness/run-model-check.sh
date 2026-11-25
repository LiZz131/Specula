#!/usr/bin/env bash
# Campaign plan executed in this run (each line = one bounded TLC campaign via
# harness/tlc-run.sh; exact commands are recorded in each spec/output/<label>.log).
# Lanes may run concurrently; workers are sized for a 40-core host.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
R=harness/tlc-run.sh
case "${1:-all}" in
  standard)   bash $R MC MC.cfg mc-standard 12 30 -coverage 10
              bash $R MC MC-membership.cfg mc-membership 4 20 ;;
  sim-standard) bash $R MC MC.cfg mc-standard-sim 8 20 -simulate num=999999999 -depth 60 ;;
  full)       bash $R Update Update_full.cfg update-full 12 30
              bash $R Update Update_full_cont1.cfg update-full-cont1 12 30
              bash $R Update Update_full_cont2.cfg update-full-cont2 12 30 ;;
  sim-full)   bash $R Update Update_full_cont2.cfg update-full-cont2-sim 8 20 -simulate num=999999999 -depth 60 ;;
  focused)    bash $R Update Update_focused_cont.cfg update-focused-cont 12 30 ;;
  sim-focused) bash $R Update Update_focused_cont.cfg update-focused-cont-sim 8 15 -simulate num=999999999 -depth 80 ;;
  open)       bash $R Update Update_open_cont.cfg update-open-cont 12 30 ;;
  discharge)  bash $R Update Update_discharge_membership.cfg discharge-membership 6 15
              bash $R Update Update_discharge.cfg discharge-full 6 20 ;;
  mixed)      bash $R Update Update_full_mixed_cont.cfg update-full-mixed-cont 8 20 ;;
  hunts)      bash $R Update MC_hunt_leader_abdication.cfg hunt-leader-abdication-bfs 4 20
              bash $R Update MC_hunt_stale_round.cfg hunt-stale-round-bfs 4 20
              bash $R Update MC_hunt_prevote_panic.cfg hunt-prevote-panic-bfs 8 30
              bash $R Update MC_hunt_prevote_crash_cont.cfg hunt-prevote-crash-bfs 8 20 ;;
  sim-panic)  bash $R Update MC_hunt_prevote_panic.cfg hunt-prevote-panic-sim 8 20 -simulate num=999999999 -depth 60 ;;
  canaries)   for c in CanaryNoCertifiedLeader CanaryNoLeaderWithTimerRound CanaryNoPreVoteElection CanaryNoPreVoteTally \
                       CanaryNoPreVoteLeaseReject CanaryNoGreaterLogFromPreVote CanaryNoPreCandidateDroppedByFollowing \
                       CanaryNoSameLeaderIdNewRound; do bash $R Update Canary_$c.cfg canary-$c 6 10; done ;;
  all)        for s in standard full discharge hunts focused open mixed canaries sim-standard sim-full sim-focused sim-panic; do "$0" $s; done ;;
esac
