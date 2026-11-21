#!/usr/bin/env bash
cd /work/current/.specula-output/spec
SIM="-simulate num=999999999 -depth 100"
./run_tlc.sh hunt_us4_focused Update.tla Update_hunt_us4_focused.cfg 1500 8 20g &
./run_tlc.sh sim_us4_full Update.tla Update_hunt_us4_sim.cfg 1500 8 16g $SIM &
wait
echo BATCH3A-DONE
