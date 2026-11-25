#!/usr/bin/env bash
# Reachability canaries: each cfg asserts a scenario is unreachable; a reported
# violation is the expected witness (non-vacuity evidence).
cd "$(dirname "${BASH_SOURCE[0]}")"
for c in prevote_elect leader_stale_round grant_response reject_response nonvoter_round; do
    SPECULA_TLC_HEAP=8g ./run-tlc.sh Update Update_canary_$c.cfg canary-$c 10 3
done
