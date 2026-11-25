#!/usr/bin/env bash
# V1 incremental model-checking campaign (final model). Five lanes run
# concurrently; each run is bounded by TLC stopAfter plus an outer timeout.
# States: /dev/shm/specula-e2e-case-002/<id> (removed per run); logs:
# spec/output/incremental/runs/<id>.log; ledger: runs/ledger.ndjson.
cd /work/current/.specula-output/spec
R=./run-tlc.sh
lane1() {
  STOP_AFTER=1800 WORKERS=8 HEAP=32g $R mc-standard-bfs MC.tla MC.cfg 2400s
  STOP_AFTER=1800 WORKERS=8 HEAP=32g $R mc-standard-filtered-bfs MCFiltered.tla MC-filtered.cfg 2400s
}
lane2() {
  STOP_AFTER=1800 WORKERS=8 HEAP=16g $R mc-standard-filtered-sim MCFiltered.tla MC-filtered.cfg 2400s -simulate num=999999999 -depth 80
  STOP_AFTER=900 WORKERS=8 HEAP=24g $R base-bfs base.tla base.cfg 1300s
  for h in election mutation recovery sync; do STOP_AFTER=600 WORKERS=8 HEAP=8g $R v0-hunt-$h MC.tla MC-hunt-$h.cfg 900s; done
  for c in NotUpToDateReached NotNonDurableNewLeaderAckReached NotAckShadowReached NotInitialExitFlushedReached; do STOP_AFTER=600 WORKERS=8 HEAP=8g $R canary-$c Update.tla Update-canary-$c.cfg 900s; done
  STOP_AFTER=900 WORKERS=8 HEAP=16g $R canary-NotCertifiedLossReached HuntU1.tla HuntU1-canary-certloss.cfg 1300s
}
lane3() {
  for i in 1 2 4 5 3; do STOP_AFTER=900 WORKERS=8 HEAP=24g $R upd-full-P$i-bfs Update.tla Update-full-P$i.cfg 1300s; done
}
lane4() {
  for i in 1 2 4 5 3; do STOP_AFTER=900 WORKERS=8 HEAP=24g $R upd-focused-P$i-bfs Update.tla Update-focused-P$i.cfg 1300s; done
}
lane5() {
  for p in CertifiedDurableOnQuorum NewLeaderAckIsFirstAck VotingHistoryCoversDurable; do STOP_AFTER=900 WORKERS=8 HEAP=16g $R hunt2s-$p-bfs Update.tla Update-hunt2s-$p.cfg 1300s; done
  STOP_AFTER=1800 WORKERS=8 HEAP=24g $R huntU1-P3-bfs HuntU1.tla HuntU1-P3.cfg 2400s
  STOP_AFTER=1800 WORKERS=8 HEAP=24g $R huntU1-P3-crash-bfs HuntU1.tla HuntU1-P3-crash.cfg 2400s
  STOP_AFTER=900 WORKERS=8 HEAP=24g $R upd-discharge-bfs Update.tla Update-discharge.cfg 1300s
  STOP_AFTER=900 WORKERS=8 HEAP=24g $R upd-open-bfs Update.tla Update-open.cfg 1300s
  for i in 2 3 4 5; do STOP_AFTER=600 WORKERS=8 HEAP=16g $R upd-full-P$i-sim Update.tla Update-full-P$i.cfg 900s -simulate num=999999999 -depth 80; done
}
mkdir -p output/incremental/campaign
lane1 > output/incremental/campaign/lane1.out 2>&1 &
lane2 > output/incremental/campaign/lane2.out 2>&1 &
lane3 > output/incremental/campaign/lane3.out 2>&1 &
lane4 > output/incremental/campaign/lane4.out 2>&1 &
lane5 > output/incremental/campaign/lane5.out 2>&1 &
wait
echo CAMPAIGN-DONE
