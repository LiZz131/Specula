#!/usr/bin/env bash
# Re-run the case-002 decision probes on the arms' exported final specs.
#   ./run.sh <arm> <cfg-basename> [timeout-seconds]           e.g. ./run.sh v1 P-npe-tgt
#   JSON=<trace.ndjson> MODULE=Trace ./run.sh v0 Tr-OAL       trace replay with the original OneActiveLeaderPerEpoch
# Copies results/<arm>/case-002/r1/output/spec/*.{tla,cfg} into a temp dir, adds Probe002.tla and the probe
# cfg from this directory, and runs TLC (BFS, no deadlock check). Needs java, tla2tools.jar and, for trace
# replays, CommunityModules-deps.jar ($TLA_JARS, default: the Specula checkout's lib/ jars).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); arm=$1; cfg=$2; t=${3:-1800}; mod=${MODULE:-Probe002}
spec="$here/../../../../results/$arm/case-002/r1/output/spec"
lib="$here/../../../../../../../lib"
jars=${TLA_JARS:-"$lib/tla2tools.jar:$lib/CommunityModules-deps.jar"}
w=$(mktemp -d); cp "$spec"/*.tla "$spec"/*.cfg "$w"/; cp "$here/$arm/Probe002.tla" "$here/$arm/$cfg.cfg" "$w"/
cd "$w" && timeout "$t" java -Xmx16g -XX:+UseParallelGC -cp "$jars" tlc2.TLC -workers "${WORKERS:-8}" -deadlock -config "$cfg.cfg" "$mod.tla" | tee "$here/$arm/$cfg.rerun.log"
SPEC_DIR="$w" python3 "$here/cex_steps.py" "$here/$arm/$cfg.rerun.log" || true
