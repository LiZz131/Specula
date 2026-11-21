#!/usr/bin/env bash
cd /work/current/.specula-output/spec
TLC_WORKERS=12 ./run_tlc.sh Update.tla Update_hunt_U5_deep_safety.cfg hunt-U5_deep_safety bfs 30 &
TLC_WORKERS=12 SIM_DEPTH=100 ./run_tlc.sh Update.tla Update_sim_deep_safety.cfg sim-deep-safety sim 30 &
TLC_WORKERS=8 SIM_DEPTH=100 ./run_tlc.sh MC.tla MC_hunt_scenario1_params.cfg sim-scenario1_params sim 15 &
wait
echo "deep campaign done"
