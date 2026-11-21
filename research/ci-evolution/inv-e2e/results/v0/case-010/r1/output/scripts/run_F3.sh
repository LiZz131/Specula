#!/usr/bin/env bash
cd /work/current/.specula-output/spec
T=../scripts/tlc.sh
TLC_HEAP=16g $T Update Update-hunt-snap-steered-oldcontrol-consequence.cfg final3-update-hunt-snap-steered-oldcontrol-consequence-bfs 20m -workers 8 -checkpoint 0 &
TLC_HEAP=10g $T Update Update-canary-trunc-steered2.cfg final3-update-canary-trunc-steered2-sim 20m -simulate num=999999999 -depth 200 -workers 6 &
TLC_HEAP=10g $T Update Update-hunt-diffwindow-steered2.cfg final3-update-hunt-diffwindow-steered2-sim 20m -simulate num=999999999 -depth 200 -workers 6 &
TLC_HEAP=10g $T Update Update-hunt-trunc-steered2.cfg final3-update-hunt-trunc-steered2-sim 20m -simulate num=999999999 -depth 200 -workers 6 &
( for h in commit apply snapshot recovery; do TLC_HEAP=8g $T MC MC-$h-hunt.cfg final3-mc-$h-hunt-sim 6m -simulate num=999999999 -depth 120 -workers 4; done ) &
wait
