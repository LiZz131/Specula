#!/usr/bin/env bash
# epoch-2 driver: one rep for case-011 then case-002, arms v2 v0 v1 one at a time; export each run.
# Agents get Specula main's MCP tools (--main-tools; needs a build_main_tools.py build).
#   epoch2-round.sh REP              round-1 setup (as run on 2026-11-24/25): epoch-1 names, no specular CLI,
#                                    WORK/main-tools
#   epoch2-round.sh REP specular     Specular v1.5 names + CLI: prepares each cell with --layout specular
#                                    against $MAIN_TOOLS (default WORK/main-tools-specular)
# Overridable: INV_E2E_WORK, INV_E2E_RESULTS, MAIN_TOOLS, CASES ("case-011 case-002"), ARMS ("v2 v0 v1").
# run.py waits before each claude run until the host OAuth token outlives the run (timeout + 30 min).
set -u
REP=$1
LAYOUT=${2:-specula}
export INV_E2E_WORK=${INV_E2E_WORK:-/mydata/bingzhuo/inv-e2e-epoch2}
export INV_E2E_RESULTS=${INV_E2E_RESULTS:-/users/bingzhuo/Specula/research/ci-evolution/inv-e2e/results-epoch2}
MT=${MAIN_TOOLS:-$INV_E2E_WORK/main-tools-specular}
cd /users/bingzhuo/Specula/research/ci-evolution/inv-e2e
for c in ${CASES:-case-011 case-002}; do
  for a in ${ARMS:-v2 v0 v1}; do
    echo "$(date '+%F %T') START $a $c r$REP layout=$LAYOUT"
    if [ "$LAYOUT" = specular ]; then
      [ -e "$INV_E2E_WORK/attempts/$a/$c/r$REP/attempt.json" ] || \
        python3 prepare.py --arm $a --case $c --rep $REP --layout specular --main-tools "$MT"
      python3 run.py --main-tools --main-tools-dir "$MT" --arm $a --case $c --rep $REP
    else
      python3 run.py --main-tools --arm $a --case $c --rep $REP
    fi
    echo "$(date '+%F %T') RUN-EXIT $a $c r$REP rc=$?"
    python3 export.py runs --arm $a --case $c --rep $REP
    echo "$(date '+%F %T') EXPORTED $a $c r$REP rc=$?"
  done
done
echo "$(date '+%F %T') ROUND-DONE r$REP"
