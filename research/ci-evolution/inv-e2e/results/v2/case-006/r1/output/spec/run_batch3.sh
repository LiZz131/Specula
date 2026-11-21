#!/usr/bin/env bash
cd "$(dirname "$0")"
./run_tlc.sh upd_focused_rest Update.tla Update_focused_rest.cfg bfs 20 8 > output/batch3-upd_focused_rest.out 2>&1 &
./run_tlc.sh upd_focused_rest_sim Update.tla Update_focused_rest.cfg sim 20 6 > output/batch3-upd_focused_rest_sim.out 2>&1 &
./run_tlc.sh upd_full_rest_sim Update.tla Update_full_rest.cfg sim 20 6 > output/batch3-upd_full_rest_sim.out 2>&1 &
./run_tlc.sh upd_hunt_forwarded_rest Update.tla Update_hunt_forwarded_rest.cfg bfs 20 6 > output/batch3-upd_hunt_forwarded_rest.out 2>&1 &
wait
cat output/batch3-*.out
