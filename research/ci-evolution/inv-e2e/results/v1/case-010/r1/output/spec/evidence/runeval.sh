#!/usr/bin/env bash
# usage: runeval.sh <id>
cd "$(dirname "$0")/$1"
M=/dev/shm/specula-e2e-case-010/ev-$1-$$
CMD="java -DTLA-Library=/work/current/.specula-output/spec:/work/current/.specula-output/spec/evidence -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -workers 1 -metadir $M -config $1.cfg $1"
echo "CMD: timeout 5m $CMD" > tlc.log
timeout 5m $CMD >> tlc.log 2>&1; echo "exit=$?" >> tlc.log
rm -rf "$M"
grep -E '^<<"' tlc.log | head -3; grep -E "Error|exit=" tlc.log | head -3
