#!/usr/bin/env bash
cd "$(dirname "$0")"
./run_tlc.sh mc_standard MC.tla MC.cfg bfs 20 8 > output/batch1-mc_standard.out 2>&1 &
./run_tlc.sh upd_full Update.tla Update_full.cfg bfs 20 8 > output/batch1-upd_full.out 2>&1 &
./run_tlc.sh upd_full_rest Update.tla Update_full_rest.cfg bfs 20 6 > output/batch1-upd_full_rest.out 2>&1 &
./run_tlc.sh upd_focused Update.tla Update_focused.cfg bfs 20 6 > output/batch1-upd_focused.out 2>&1 &
./run_tlc.sh upd_hunt_stale_ack Update.tla Update_hunt_stale_ack.cfg bfs 20 6 > output/batch1-upd_hunt_stale_ack.out 2>&1 &
( for c in reuse reuse_served stale_ack forwarded_freed leader_stepdown; do
    ./run_tlc.sh reach_update_$c Update.tla Reach_update_$c.cfg bfs 10 2
  done
  ./run_tlc.sh mc_complete_core MC.tla MC_complete_core.cfg bfs 15 2 ) > output/batch1-canaries.out 2>&1 &
wait
cat output/batch1-*.out
