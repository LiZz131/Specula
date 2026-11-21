#!/usr/bin/env bash
# Simulation follow-ups (30 min each, depth 100), run concurrently; blocks until all finish.
cd "$(dirname "$0")/.."
export TLC_STOP_AFTER=1800 TLC_TIMEOUT=35m TLC_WORKERS=9 TLC_HEAP=24g
tools/tlc.sh sim/MC_hunt_scenario1_params_sim MC.tla MC_hunt_scenario1_params.cfg -simulate -depth 100 &
tools/tlc.sh sim/Update_sim_deep_core Update.tla Update_sim_deep_core.cfg -simulate -depth 100 -dumpTrace json output/sim/Update_sim_deep_core.cex.json &
tools/tlc.sh sim/Update_hunt_scenario5_ve_recovery_core_sim Update.tla Update_hunt_scenario5_ve_recovery_core.cfg -simulate -depth 100 &
tools/tlc.sh sim/Update_hunt_scenario4_ve_lifecycle_core_sim Update.tla Update_hunt_scenario4_ve_lifecycle_core.cfg -simulate -depth 100 &
wait
echo all-simulations-done
