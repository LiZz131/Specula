#!/usr/bin/env bash
# Final incremental model-checking campaign (Part 3).  Every run is bounded by
# an outer timeout and by the TimeBudget constraint; states under /dev/shm.
cd /work/current/.specula-output/spec
R=./run-tlc.sh
echo "== wave 1 (short: canaries, U1/U2/U4 focused + hunts, inherited hunts, old controls) $(date -u)"
TLC_HEAP=6g $R final-reach-nlack-logged reachability 2100s Update.tla Update-reach-nlack-logged.cfg -- -workers 3 &
TLC_HEAP=6g $R final-reach-uptodate reachability 2100s Update.tla Update-reach-uptodate.cfg -- -workers 3 &
TLC_HEAP=6g $R final-reach-activate reachability 2100s Update.tla Update-reach-activate.cfg -- -workers 3 &
TLC_HEAP=8g $R final-reach-recovery-shape reachability 2100s Update.tla Update-reach-recovery-shape.cfg -- -workers 4 &
TLC_HEAP=6g $R final-focused-ackdurable update-focused-bfs 2100s Update.tla Update-focused-ackdurable.cfg -- -workers 3 &
TLC_HEAP=6g $R final-focused-quorumdurable update-focused-bfs 2100s Update.tla Update-focused-quorumdurable.cfg -- -workers 3 &
TLC_HEAP=6g $R final-hunt-postact-crash update-scenario-hunt 2100s Update.tla Update-hunt-postact-crash.cfg -- -workers 3 &
TLC_HEAP=6g $R final-hunt-postact-leak update-scenario-hunt 2100s Update.tla Update-hunt-postact-leak.cfg -- -workers 3 &
TLC_HEAP=4g $R final-oldcontrol-ackdurable update-old-control 2100s Update.tla evidence/old-control/Update-focused-ackdurable-old.cfg -- -workers 2 &
TLC_HEAP=4g $R final-oldcontrol-quorumdurable update-old-control 2100s Update.tla evidence/old-control/Update-focused-quorumdurable-old.cfg -- -workers 2 &
for h in sync recovery mutation election; do TLC_HEAP=3g $R final-mc-hunt-$h inherited-hunt 2100s MC.tla MC-hunt-$h.cfg -- -workers 2 & done
wait
echo "== wave 2 (30-min: standard MC, full update, focused control/completeness/syncedlog, admission) $(date -u)"
TLC_HEAP=24g $R final-mc-standard standard-mc-bfs 2100s MC.tla MC.cfg -- -workers 8 &
TLC_HEAP=16g $R final-update-full update-full-bfs 2100s Update.tla Update-full.cfg -- -workers 6 &
TLC_HEAP=16g $R final-focused-control update-focused-bfs 2100s Update.tla Update-focused.cfg -- -workers 6 &
TLC_HEAP=16g $R final-focused-completeness update-focused-bfs 2100s Update.tla Update-focused-completeness.cfg -- -workers 6 &
TLC_HEAP=16g $R final-focused-syncedlog update-focused-bfs 2100s Update.tla Update-focused-syncedlog.cfg -- -workers 5 &
TLC_HEAP=10g $R final-hunt-postact-full update-admission 2100s Update.tla Update-hunt-postact-full.cfg -- -workers 4 &
TLC_HEAP=10g $R final-hunt-postact-syncedlog update-scenario-hunt 2100s Update.tla Update-hunt-postact-syncedlog.cfg -- -workers 4 &
wait
echo "== wave 3 (30-min: open, discharge, recovery-full, base, MC-small, simulations) $(date -u)"
TLC_HEAP=12g $R final-update-open update-open-bfs 2100s Update.tla Update-open.cfg -- -workers 6 &
TLC_HEAP=12g $R final-update-discharge update-discharge 2100s Update.tla Update-discharge.cfg -- -workers 6 &
TLC_HEAP=12g $R final-update-recovery-full update-admission 2100s Update.tla Update-recovery-full.cfg -- -workers 6 &
TLC_HEAP=16g $R final-base-standard standard-base-bfs 2100s base.tla base.cfg -- -workers 8 &
TLC_HEAP=6g $R final-mc-small standard-mc-bfs 2100s MC.tla MC-small.cfg -- -workers 4 &
TLC_HEAP=8g $R final-sim-update-full update-full-simulation 2100s Update.tla Update-full.cfg -- -workers 5 -simulate -depth 100 &
TLC_HEAP=8g $R final-sim-mc-standard standard-mc-simulation 2100s MC.tla MC-sim.cfg -- -workers 5 -simulate -depth 100 &
wait
echo "== done $(date -u)"
rm -rf /dev/shm/specula-e2e-case-002/*
