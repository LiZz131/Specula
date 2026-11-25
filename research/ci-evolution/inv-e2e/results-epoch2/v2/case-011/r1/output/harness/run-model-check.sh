#!/usr/bin/env bash
# Incremental model-checking campaign (Update-Focused Checking order).
# Each run: bounded by outer timeout + tlc2.TLC.stopAfter (budget), states in
# /dev/shm/specula-e2e-case-011/mc-<label> (removed), log spec/output/mc-<label>.log.
# Budget-terminated runs (queue left) are LIMITED_COVERAGE, never exhaustive.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
B="${SPECULA_MC_MINUTES:-30}"; S="${SPECULA_SIM_MINUTES:-20}"
# 0. Standard convergence round (reference suite)
./run-tlc.sh MC MC.cfg std-MC "$B" 14 -coverage 10
./run-tlc.sh MC MC-membership.cfg std-MC-membership "$B" 6 -coverage 10
# 1. Full update check over complete MCNext: stops at the first violation
#    (MC-1); the filtered variant prunes the two analyzed counterexamples
#    (ACTION_CONSTRAINT KnownFindingsFilter) and keeps exploring.
./run-tlc.sh Update Update_full.cfg update-full "$B" 14 -coverage 10
./run-tlc.sh Update Update_full_filtered.cfg update-full-filtered "$B" 14 -coverage 10
# 2. Concrete focused; 3. open focused + discharge (filtered variants)
./run-tlc.sh Update Update_focused_filtered.cfg update-focused-filtered "$B" 10 -coverage 10
./run-tlc.sh Update Update_open_filtered.cfg update-open-filtered "$B" 10 -coverage 10
./run-tlc.sh Update Update_discharge.cfg update-discharge "$B" 10 -coverage 10
# 4. Scenario hunts. Attribution run first (unfiltered, elections only via Pre-Vote).
./run-tlc.sh Update MC_hunt_prevote_leader_object.cfg hunt-leader_object-bfs "$B" 6 -coverage 10
for h in prevote_stale_round prevote_membership prevote_default_rpc prevote_single_voter prevote_leader_object; do
    ./run-tlc.sh Update MC_hunt_${h}_filtered.cfg hunt-$h-filtered-bfs "$B" 8 -coverage 10
    ./run-tlc.sh Update MC_hunt_${h}_filtered.cfg hunt-$h-filtered-sim "$S" 8 -simulate num=999999999 -depth 60
done
# Continued hunts after D-2 / MC-2 counterexamples (properties disabled, see cfg headers)
for h in membership single_voter; do
    ./run-tlc.sh Update MC_hunt_prevote_${h}_filtered_nog.cfg hunt-prevote_${h}-filtered-nog-bfs "$B" 8 -coverage 10
    ./run-tlc.sh Update MC_hunt_prevote_${h}_filtered_nog.cfg hunt-prevote_${h}-filtered-nog-sim "$S" 8 -simulate num=999999999 -depth 60
done
# Reachability canaries
./run-canaries.sh
