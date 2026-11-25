#!/usr/bin/env bash
# Follow-up runs on the final model: known MC-2 (U4) class filtered via
# FilterKnownU4 (exploration-only), fixed open spec (EnvUpdate conjunct order,
# rollback frame), re-run of discharge with the strengthened rely frame.
cd /work/current/.specula-output/spec
R=./run-tlc.sh
f1() {
  STOP_AFTER=1800 WORKERS=8 HEAP=32g $R mc-standard-filtered2-bfs MCFiltered.tla MC-filtered.cfg 2400s
  STOP_AFTER=900 WORKERS=8 HEAP=16g $R upd-open-bfs-v2 Update.tla Update-open.cfg 1300s
}
f2() {
  for i in 2 3; do STOP_AFTER=900 WORKERS=8 HEAP=24g $R upd-full-P$i-filtered-bfs UpdateFiltered.tla Update-full-P$i-filtered.cfg 1300s; done
  STOP_AFTER=900 WORKERS=8 HEAP=24g $R upd-discharge-bfs-v2 Update.tla Update-discharge.cfg 1300s
}
f3() {
  for i in 2 3; do STOP_AFTER=900 WORKERS=8 HEAP=24g $R upd-focused-P$i-filtered-bfs UpdateFiltered.tla Update-focused-P$i-filtered.cfg 1300s; done
  for i in 2 3; do STOP_AFTER=600 WORKERS=8 HEAP=16g $R upd-focused-P$i-filtered-sim UpdateFiltered.tla Update-focused-P$i-filtered.cfg 900s -simulate num=999999999 -depth 80; done
}
mkdir -p output/incremental/campaign
f1 > output/incremental/campaign/followup1.out 2>&1 &
f2 > output/incremental/campaign/followup2.out 2>&1 &
f3 > output/incremental/campaign/followup3.out 2>&1 &
wait
echo FOLLOWUPS-DONE
