#!/usr/bin/env bash
# Re-run the case-006 decision probes on the arms' exported final specs.
#   ./run.sh <arm> <cfg-basename> [timeout-seconds]           e.g. ./run.sh v1 P-stale-guided
# Copies results/<arm>/case-006/r1/output/spec/*.{tla,cfg} into a temp dir, adds Probe006.tla and the probe
# cfg from this directory, and runs TLC (BFS, no deadlock check). Needs java and tla2tools.jar
# ($TLA_JARS, default: the Specula checkout's lib/ jars).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); arm=$1; cfg=$2; t=${3:-1800}; mod=${MODULE:-Probe006}
spec="$here/../../../../results/$arm/case-006/r1/output/spec"
lib="$here/../../../../../../../lib"
jars=${TLA_JARS:-"$lib/tla2tools.jar:$lib/CommunityModules-deps.jar"}
w=$(mktemp -d); cp "$spec"/*.tla "$spec"/*.cfg "$w"/; cp "$here/$arm/Probe006.tla" "$here/$arm/$cfg.cfg" "$w"/
cd "$w" && timeout "$t" java -Xmx16g -XX:+UseParallelGC -cp "$jars" tlc2.TLC -workers "${WORKERS:-8}" -deadlock -config "$cfg.cfg" "$mod.tla" | tee "$here/$arm/$cfg.rerun.log"
SPEC_DIR="$w" python3 "$here/cex_steps.py" "$here/$arm/$cfg.rerun.log" || true
