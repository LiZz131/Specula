#!/usr/bin/env bash
# Re-run the case-012 decision probes on the arms' exported final specs.
#   ./run.sh <arm> <cfg-basename> [timeout-seconds]      e.g. ./run.sh v1 P-J-full
# Copies results/<arm>/case-012/r1/output/spec/*.{tla,cfg} into a temp dir, adds Probe012.tla and the
# probe cfg from this directory, and runs TLC (BFS, no deadlock check). Needs java and tla2tools.jar
# ($TLA_JARS, default: the Specula checkout's lib/tla2tools.jar).
#   python3 vecprogress_diff.py [steps] [maxval]   differential execution, VecProgress port vs GreatestQuorumValue
#   python3 vecprogress_diff.py --conform <ndjson>... replay the arms' real ProgressUpdate events on the port
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); arm=$1; cfg=$2; t=${3:-1800}
spec="$here/../../../../results/$arm/case-012/r1/output/spec"
jars=${TLA_JARS:-"$here/../../../../../../../lib/tla2tools.jar"}
w=$(mktemp -d); cp "$spec"/*.tla "$spec"/*.cfg "$w"/; cp "$here/$arm/Probe012.tla" "$here/$arm/$cfg.cfg" "$w"/
cd "$w" && timeout "$t" java -Xmx10g -XX:+UseParallelGC -cp "$jars" tlc2.TLC -workers "${WORKERS:-8}" -deadlock -config "$cfg.cfg" Probe012.tla | tee "$here/$arm/$cfg.rerun.log"
python3 "$here/cex_steps.py" "$here/$arm/$cfg.rerun.log" || true
