#!/usr/bin/env bash
# Usage: sany.sh <Module.tla> [log]   (fails on any parse/semantic error)
set -uo pipefail
cd /work/current/.specula-output/spec
OUT=$(timeout 5m java -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tla2sany.SANY "$1" 2>&1)
rc=$?
[ -n "${2:-}" ] && echo "$OUT" > "$2"
if echo "$OUT" | grep -qiE "error|Unknown operator|Abort"; then echo "$OUT" | grep -iE -A4 "error|Unknown operator" | head -20; echo "sany FAILED"; exit 1; fi
echo "sany OK ($1)"; exit $rc
