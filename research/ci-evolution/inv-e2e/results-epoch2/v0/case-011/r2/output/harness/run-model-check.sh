#!/usr/bin/env bash
# Model-checking campaign for the Pre-Vote update (incremental order).
# Each run: bounded by an outer timeout (planned budget => LIMITED_COVERAGE),
# states under /dev/shm/specular-e2e-case-011/, removed after the run.
set -euo pipefail
h="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
run() { "$h/tlc-run.sh" "$@"; }

# 0. Reachability canaries (each invariant is expected to be violated).
for c in CanaryPreVoteRoundStarted CanaryPreVoteGranted CanaryPreVoteLeaseRejected \
         CanaryElectedViaPreVote CanaryCandidateWithPreVoteRound CanaryLeaderWithPreVoteRound; do
  run Update "Update-canary-$c.cfg" "canary-$c" 10 4 8g
done
# 1. Standard round + inherited companion + regression control (batch 1).
run MC MC.cfg mc-standard 30 10 24g -coverage 5 &
run Update Update.cfg update-full 30 8 20g &
run Update Update-control-off.cfg update-control-off 30 6 16g &
run MC MC-prevote-off.cfg mc-prevote-off 30 6 16g &
run MC MC-membership.cfg mc-membership 30 4 12g -coverage 5 &
wait
run Update Update-nofault.cfg update-nofault 12 2 6g
# 2. Focused / open / discharge / residual / toggle (batch 2).
run Update Update-focused.cfg update-focused 30 4 12g &
run Update Update-open.cfg update-open 30 4 12g &
run Update Update-discharge.cfg update-discharge 30 14 24g &   # re-run after the rely repair
run Update Update-residual.cfg update-residual 30 8 20g &
run Update Update-focused-residual.cfg update-focused-residual 30 4 12g &
run Update Update-open-residual.cfg update-open-residual 30 4 12g &
run Update Update-toggle.cfg update-toggle 30 4 12g &
wait
# 3. Simulation follow-ups for configs whose BFS did not exhaust.
run MC MC.cfg mc-standard-sim 30 7 12g -simulate num=999999999 -depth 60 &
run Update Update-residual.cfg update-residual-sim 30 7 12g -simulate num=999999999 -depth 60 &
run Update Update-focused-residual.cfg update-focused-residual-sim 30 2 6g -simulate num=999999999 -depth 60 &
run Update Update-toggle.cfg update-toggle-sim 30 2 6g -simulate num=999999999 -depth 60 &
wait
run Update Update-open.cfg update-open-sim 30 15 14g -deadlock -simulate num=999999999 -depth 60 &
run Update Update-open-residual.cfg update-open-residual-sim 30 15 14g -deadlock -simulate num=999999999 -depth 60 &
run Update Update-discharge.cfg update-discharge-sim 30 10 12g -simulate num=999999999 -depth 60 &
wait
# 4. Prior-equivalence regression (scratch copy with the two prior-model repairs reverted).
(cd "$h/../spec/regression-prior-equivalence" && timeout 25m java -Xmx8g -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar \
   tlc2.TLC -workers 4 -metadir /dev/shm/specular-e2e-case-011/prior-eq -config MC-prevote-off.cfg MC \
   > ../output/regression-prior-equivalence.log 2>&1; rm -rf /dev/shm/specular-e2e-case-011/prior-eq)
python3 -I "$h/summarize-mc.py" "$h/../spec/output"
