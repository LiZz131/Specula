#!/usr/bin/env bash
cd "$(dirname "$0")"
./run_tlc.sh upd_hunt_linearizable Update.tla Update_hunt_linearizable.cfg bfs 20 8 > output/batch2-upd_hunt_linearizable.out 2>&1 &
./run_tlc.sh upd_hunt_linearizable_sim Update.tla Update_hunt_linearizable.cfg sim 30 8 > output/batch2-upd_hunt_linearizable_sim.out 2>&1 &
wait
cat output/batch2-upd_hunt_linearizable*.out
