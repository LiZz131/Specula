#!/usr/bin/env bash
cd "$(dirname "$0")"
./run_tlc.sh upd_open Update.tla Update_open.cfg bfs 20 4 > output/batch2-upd_open.out 2>&1 &
./run_tlc.sh upd_discharge Update.tla Update_discharge.cfg bfs 20 4 > output/batch2-upd_discharge.out 2>&1 &
./run_tlc.sh upd_hunt_forwarded Update.tla Update_hunt_forwarded.cfg bfs 20 4 > output/batch2-upd_hunt_forwarded.out 2>&1 &
./run_tlc.sh upd_hunt_linearizable_directed Update.tla Update_hunt_linearizable_directed.cfg bfs 25 8 > output/batch2-upd_hunt_linearizable_directed.out 2>&1 &
./run_tlc.sh upd_full_sim Update.tla Update_full.cfg sim 20 6 > output/batch2-upd_full_sim.out 2>&1 &
( ./run_tlc.sh reach_update_leader_stepdown Update.tla Reach_update_leader_stepdown.cfg bfs 10 2
  for s in s1_leader s2_commit s3_quorum s4_ready_read s5_forwarded_read; do ./run_tlc.sh reach_v0_$s MC.tla Reach_$s.cfg bfs 10 2; done
  for h in s1_election s2_replication s3_quorum s4_readindex s5_forwarded_read; do ./run_tlc.sh hunt_v0_$h MC.tla MC_hunt_$h.cfg bfs 10 2; done
) > output/batch2-inherited.out 2>&1 &
wait
cat output/batch2-upd_open.out output/batch2-upd_discharge.out output/batch2-upd_hunt_forwarded.out output/batch2-upd_hunt_linearizable_directed.out output/batch2-upd_full_sim.out output/batch2-inherited.out
