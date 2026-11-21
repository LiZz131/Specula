#!/usr/bin/env bash
# Reachability canaries / inherited hunts re-run on the final model.
cd /work/current/.specula-output/spec
T=../scripts/tlc.sh
for c in canary-snapabort canary-reload canary-diffabort canary-snaponly-steered-reload canary-snaponly-steered-snapcommit canary-diffwindow-steered2; do
  TLC_HEAP=6g $T Update Update-$c.cfg final6-update-$c-bfs 10m -workers 4 -checkpoint 0 &
done
TLC_HEAP=6g $T Update Update-canary-trunc-steered2.cfg final6-update-canary-trunc-steered2-sim 10m -simulate num=999999999 -depth 200 -workers 4 &
( for h in election sync snapshot recovery; do TLC_HEAP=4g $T MC MC-$h-hunt.cfg final6-mc-$h-hunt-bfs 10m -workers 2 -checkpoint 0; done ) &
( for h in commit apply; do TLC_HEAP=4g $T MC MC-$h-hunt.cfg final6-mc-$h-hunt-sim 6m -simulate num=999999999 -depth 120 -workers 2; done ) &
wait
