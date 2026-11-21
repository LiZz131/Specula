#!/usr/bin/env bash
# Batch 2: inherited V0 hunts/canaries on the V1 suite, focused US4 BFS,
# US3 hunt on full MCNext without faults, simulation follow-ups.
cd /work/current/.specula-output/spec
SIM="-simulate num=999999999 -depth 100"
( for h in s1_election s2_replication s3_quorum; do ./run_tlc.sh mc_hunt_$h MC.tla MC_hunt_$h.cfg 900 4 10g; done ) &
( for h in s4_readindex s5_forwarded_read; do ./run_tlc.sh mc_hunt_$h MC.tla MC_hunt_$h.cfg 900 4 10g; done ) &
( ./run_tlc.sh mc_complete_core MC.tla MC_complete_core.cfg 900 4 10g
  for r in Reach_s1_leader Reach_s2_commit Reach_s3_quorum Reach_s4_ready_read Reach_s5_forwarded_read; do ./run_tlc.sh reach_v0_${r#Reach_} MC.tla $r.cfg 600 2 6g; done ) &
./run_tlc.sh hunt_us4_focused Update.tla Update_hunt_us4_focused.cfg 1500 8 20g &
./run_tlc.sh sim_us4_full Update.tla Update_hunt_us4_sim.cfg 1500 8 16g $SIM &
./run_tlc.sh sim_mc_standard MC.tla MC.cfg 1200 4 8g $SIM &
wait
echo BATCH2-DONE
