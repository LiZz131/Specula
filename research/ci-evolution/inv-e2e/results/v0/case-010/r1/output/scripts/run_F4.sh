#!/usr/bin/env bash
# Final model (after NEWLEADER FIFO-cut repair). Re-establish violations and differential runs.
cd /work/current/.specula-output/spec
T=../scripts/tlc.sh
TLC_HEAP=16g $T Update Update-hunt-mc1-deterministic.cfg final4-update-hunt-mc1-deterministic-bfs 30m -workers 8 -checkpoint 0 &
TLC_HEAP=10g $T Update Update-hunt-trunc-steered2.cfg final4-update-hunt-trunc-steered2-sim 20m -simulate num=999999999 -depth 200 -workers 6 &
TLC_HEAP=10g $T Update Update-hunt-diffwindow-steered2.cfg final4-update-hunt-diffwindow-steered2-sim 20m -simulate num=999999999 -depth 200 -workers 5 &
TLC_HEAP=12g $T Update Update-hunt-snap-steered-oldcontrol-consequence.cfg final4-update-hunt-snap-steered-oldcontrol-consequence-bfs 20m -workers 6 -checkpoint 0 &
TLC_HEAP=6g $T Update Update-hunt-snap-steered-oldcontrol.cfg final4-update-hunt-snap-steered-oldcontrol-bfs 10m -workers 2 -checkpoint 0 &
TLC_HEAP=12g $T Update Update-hunt-snap-only-steered.cfg final4-update-hunt-snap-only-steered-bfs 20m -workers 6 -checkpoint 0 &
TLC_HEAP=12g $T MC MC.cfg final4-mc-standard-bfs 20m -workers 6 -checkpoint 0 &
wait
