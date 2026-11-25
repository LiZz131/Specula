#!/usr/bin/env bash
# Final campaign batch on the final artifacts (run after the follow-up BFS batch).
cd /work/current/.specula-output/spec
(WORKERS=16 HEAP=40g ./run-tlc.sh mc-standard-final MC.tla MC.cfg 30 > /dev/null 2>&1) &
(WORKERS=8 HEAP=12g ./run-tlc.sh mc-standard-sim-final MC.tla MC-sim.cfg 30 -simulate -depth 80 > /dev/null 2>&1) &
(WORKERS=8 HEAP=12g ./run-tlc.sh upd-full-followup-sim-r1 Update.tla Update-full-followup-sim.cfg 30 -simulate -depth 80 > /dev/null 2>&1) &
(WORKERS=6 HEAP=12g ./run-tlc.sh upd-full-followup-e3-sim-r1 Update.tla Update-full-followup-e3-sim.cfg 30 -simulate -depth 100 > /dev/null 2>&1) &
wait
