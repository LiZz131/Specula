#!/usr/bin/env bash
# Usage: tlc.sh <Spec> <cfg> <logname> <outer-timeout> [extra TLC args...]
# Runs TLC from spec/, state dir under /dev/shm/specula-e2e-case-010/, log in spec/output/.
set -uo pipefail
SPEC=$1; CFG=$2; NAME=$3; OUTER=$4; shift 4
cd /work/current/.specula-output/spec
mkdir -p output /dev/shm/specula-e2e-case-010
META=$(mktemp -d /dev/shm/specula-e2e-case-010/${NAME}.XXXX)
LOG=output/${NAME}.log
{
  echo "# cmd: timeout $OUTER java -XX:+UseParallelGC -Xmx${TLC_HEAP:-24g} -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -metadir $META -config $CFG $* $SPEC"
  echo "# started: $(date -u +%FT%TZ)"
} > "$LOG"
timeout "$OUTER" java -XX:+UseParallelGC -Xmx${TLC_HEAP:-24g} -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar \
  tlc2.TLC -metadir "$META" -config "$CFG" "$@" "$SPEC" >> "$LOG" 2>&1
RC=$?
echo "# exit: $RC finished: $(date -u +%FT%TZ)" >> "$LOG"
rm -rf "$META"
echo "rc=$RC log=$LOG"
exit 0
