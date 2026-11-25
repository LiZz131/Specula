#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE[0]}")"
SPECULA_TLC_HEAP=16g ./run-tlc.sh Update MC_hunt_prevote_membership_filtered.cfg hunt-prevote_membership-filtered-bfs 30 6 -coverage 10 &
SPECULA_TLC_HEAP=16g ./run-tlc.sh Update MC_hunt_prevote_single_voter_filtered.cfg hunt-prevote_single_voter-filtered-bfs 30 6 -coverage 10 &
wait
