#!/usr/bin/env bash
# Final-artifact checks (after the ghost repair): standard full model and the
# three counterexample-producing update campaigns.
cd /work/current/.specula-output/spec
./run_tlc.sh final_mc_standard MC.tla MC.cfg 1800 8 20g &
( ./run_tlc.sh final_update_focused Update.tla Update_focused.cfg 1200 8 16g
  ./run_tlc.sh final_hunt_us4_guided Update.tla Update_hunt_us4_guided.cfg 1800 8 20g
  ./run_tlc.sh final_update_focused_reset Update.tla Update_focused_reset.cfg 1200 8 16g ) &
wait
echo BATCH4A-DONE
