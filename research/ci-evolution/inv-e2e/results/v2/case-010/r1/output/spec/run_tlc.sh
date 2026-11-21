#!/usr/bin/env bash
# Usage: run_tlc.sh <module> <cfg> <name> <minutes> <workers> [sim-depth]
set -uo pipefail
cd /work/current/.specula-output/spec
MOD=$1; CFG=$2; NAME=$3; MIN=$4; W=$5; SIM=${6:-}
META=/dev/shm/specula-e2e-case-010/mc-$NAME-$$
mkdir -p "$META" output/mc
EXTRA=()
if [ -n "$SIM" ]; then EXTRA=(-simulate -depth "$SIM"); fi
START=$(date -u +%FT%TZ)
timeout $((MIN*60+300)) java -Xmx${TLC_HEAP:-16g} -XX:+UseParallelGC -Dtlc2.TLC.stopAfter=$((MIN*60)) \
  -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC \
  -workers "$W" -metadir "$META" -config "$CFG" "${EXTRA[@]}" -dumpTrace tla "output/mc/$NAME.cex.tla" \
  "$MOD.tla" > "output/mc/$NAME.log" 2>&1
RC=$?
rm -rf "$META"
echo "$NAME start=$START end=$(date -u +%FT%TZ) rc=$RC" | tee -a output/mc/campaign-index.txt
