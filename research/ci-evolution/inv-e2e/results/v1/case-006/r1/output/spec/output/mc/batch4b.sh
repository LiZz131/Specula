#!/usr/bin/env bash
# Final-artifact full update check, open/discharge reruns, simulation follow-ups
# for BFS runs whose diameter stayed <= 25.
cd /work/current/.specula-output/spec
SIM="-simulate num=999999999 -depth 100"
./run_tlc.sh final_update_full Update.tla Update_full.cfg 1800 6 20g &
./run_tlc.sh final_update_open Update.tla Update_open.cfg 900 4 10g &
./run_tlc.sh final_update_discharge Update.tla Update_discharge.cfg 600 4 10g &
./run_tlc.sh sim_update_full Update.tla Update_full.cfg 900 4 8g $SIM &
( ./run_tlc.sh sim_hunt_s2_replication MC.tla MC_hunt_s2_replication.cfg 600 2 6g $SIM
  ./run_tlc.sh sim_hunt_s4_readindex MC.tla MC_hunt_s4_readindex.cfg 600 2 6g $SIM ) &
( ./run_tlc.sh sim_hunt_s5_forwarded_read MC.tla MC_hunt_s5_forwarded_read.cfg 600 2 6g $SIM
  ./run_tlc.sh sim_update_focused_reset Update.tla Update_hunt_us4_focused.cfg 600 2 6g $SIM ) &
wait
echo BATCH4B-DONE
