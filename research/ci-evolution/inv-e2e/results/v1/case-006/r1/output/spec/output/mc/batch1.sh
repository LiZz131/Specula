#!/usr/bin/env bash
cd /work/current/.specula-output/spec
./run_tlc.sh mc_standard MC.tla MC.cfg 1800 8 20g &
./run_tlc.sh update_full Update.tla Update_full.cfg 1800 8 20g &
./run_tlc.sh update_focused Update.tla Update_focused.cfg 1800 8 20g &
./run_tlc.sh update_focused_reset Update.tla Update_focused_reset.cfg 1200 4 10g &
./run_tlc.sh update_open Update.tla Update_open.cfg 1200 4 10g &
./run_tlc.sh update_discharge Update.tla Update_discharge.cfg 900 4 10g &
( ./run_tlc.sh reach_update_reenqueue Update.tla Update_reach_reenqueue.cfg 600 1 4g
  ./run_tlc.sh reach_update_reuse_release Update.tla Update_reach_reuse_release.cfg 600 1 4g
  ./run_tlc.sh reach_update_reset_drop Update.tla Update_reach_reset_drop.cfg 600 1 4g ) &
wait
echo BATCH1-DONE
