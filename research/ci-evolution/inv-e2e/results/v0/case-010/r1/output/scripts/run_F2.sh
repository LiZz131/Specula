#!/usr/bin/env bash
# Final campaign batch F2 (final model). Each TLC run is bounded by an outer timeout; state dirs are removed by tlc.sh.
cd /work/current/.specula-output/spec
T=../scripts/tlc.sh
TLC_HEAP=16g $T MC MC-full.cfg final-mc-full-bfs 30m -workers 6 -checkpoint 0 &
TLC_HEAP=16g $T MC MC-wide.cfg final-mc-wide-bfs 30m -workers 6 -checkpoint 0 &
TLC_HEAP=12g $T Update Update-full.cfg final-update-full-sim 30m -simulate num=999999999 -depth 120 -workers 6 &
TLC_HEAP=12g $T Update Update-hunt-snap-only-steered.cfg final-update-hunt-snap-only-steered-bfs 30m -workers 5 -checkpoint 0 &
TLC_HEAP=12g $T Update Update-hunt-snap-only-steered-consequence.cfg final-update-hunt-snap-only-steered-consequence-bfs 30m -workers 4 -checkpoint 0 &
TLC_HEAP=8g $T Update Update-discharge.cfg final2-update-discharge-bfs 20m -workers 3 -checkpoint 0 &
( for c in snap-steered-oldcontrol snap-steered-oldcontrol-consequence; do TLC_HEAP=6g $T Update Update-hunt-$c.cfg final-update-hunt-$c-bfs 15m -workers 2 -checkpoint 0; done ) &
( for c in canary-snaponly-steered-reload canary-snaponly-steered-snapcommit canary-trunc-steered2 canary-diffwindow-steered2 canary-snapabort canary-reload canary-diffabort canary-snapcommit canary-truncabort; do TLC_HEAP=8g $T Update Update-$c.cfg final-update-$c-bfs 10m -workers 3 -checkpoint 0; done ) &
( for h in election sync commit apply snapshot recovery; do TLC_HEAP=6g $T MC MC-$h-hunt.cfg final-mc-$h-hunt-bfs 10m -workers 2 -checkpoint 0; done; TLC_HEAP=6g $T base base.cfg final-base-bfs 15m -workers 2 -checkpoint 0 ) &
wait
