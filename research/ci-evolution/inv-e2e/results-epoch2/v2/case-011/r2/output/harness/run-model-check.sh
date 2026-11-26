#!/usr/bin/env bash
# Model-checking campaigns of the incremental run (each bounded; budget-limited
# runs are LIMITED_COVERAGE, not proofs). Logs: spec/output/<name>.log.
set -uo pipefail
h="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
run() { "$h/tlc-run.sh" "$@"; }
# 1. standard convergence round
TLC_WORKERS=12 TLC_HEAP=32g run mc-standard MC.tla MC.cfg 30 -coverage 10
TLC_WORKERS=6 TLC_HEAP=16g run mc-membership MC.tla MC-membership.cfg 30 -coverage 10
# 2. update properties over full MCNext, concrete focused, open + discharge
for c in full focused open; do
  TLC_WORKERS=4 TLC_HEAP=10g run upd-$c Update.tla Update_$c.cfg 30 -dumpTrace json output/cex/upd-$c.json
  TLC_WORKERS=5 TLC_HEAP=12g run upd-$c-cont1 Update.tla Update_${c}_cont1.cfg 30 -dumpTrace json output/cex/upd-$c-cont1.json
  TLC_WORKERS=5 TLC_HEAP=12g run upd-$c-cont2 Update.tla Update_${c}_cont2.cfg 30
done
TLC_WORKERS=4 TLC_HEAP=10g run upd-discharge Update.tla Update_discharge.cfg 25
# 3. scenario hunts (+ follow-ups with known findings filtered) and canaries
TLC_WORKERS=6 TLC_HEAP=12g run upd-hunt-stale-round Update.tla Update_hunt_stale_round.cfg 30
TLC_WORKERS=4 TLC_HEAP=8g run upd-hunt-stale-round-consequence Update.tla Update_hunt_stale_round_consequence.cfg 30 -dumpTrace json output/cex/MC-1-stale-round.json
TLC_WORKERS=5 TLC_HEAP=12g run upd-hunt-nonvoter Update.tla Update_hunt_nonvoter_elect.cfg 30
TLC_WORKERS=4 TLC_HEAP=8g run upd-hunt-nonvoter-cont Update.tla Update_hunt_nonvoter_elect_cont.cfg 30 -dumpTrace json output/cex/nonvoter.json
TLC_WORKERS=6 TLC_HEAP=12g run upd-hunt-repeat-round Update.tla Update_hunt_repeat_round.cfg 30
TLC_WORKERS=6 TLC_HEAP=12g run upd-hunt-repeat-round-cont Update.tla Update_hunt_repeat_round_cont.cfg 30 -dumpTrace json output/cex/repeat-round.json
TLC_WORKERS=4 TLC_HEAP=10g run upd-hunt-default-grant Update.tla Update_hunt_default_grant.cfg 30
TLC_WORKERS=6 TLC_HEAP=12g run upd-hunt-default-grant-cont2 Update.tla Update_hunt_default_grant_cont2.cfg 30
for cfg in "$h"/../spec/Update_canary_*.cfg; do n=$(basename "$cfg" .cfg); TLC_WORKERS=4 TLC_HEAP=8g run "${n#Update_}" Update.tla "$(basename "$cfg")" 10; done
