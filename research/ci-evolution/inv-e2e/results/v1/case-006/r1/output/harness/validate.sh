#!/usr/bin/env bash
# Rebased (V1) trace-first validation: SANY all modules, then TLC replay of the
# selected fresh traces (default: all conformance configs). TLC metadirs live
# under /dev/shm/specula-e2e-case-006 and are removed after every run.
#   validate.sh [cfg ...]     (cfg names relative to spec/)
set -uo pipefail
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
SPEC_DIR="$OUTPUT_ROOT/spec"
TLA_CP="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
STATE_ROOT="/dev/shm/specula-e2e-case-006"
cd "$SPEC_DIR"
mkdir -p output/trace
CFGS=("$@")
if [ ${#CFGS[@]} -eq 0 ]; then
  CFGS=(Trace.cfg Trace_quorum_loss.cfg Trace_read_reuse.cfg Trace_stale_read.cfg Trace_read_stepdown.cfg)
fi
for m in base MC UpdateProps Update Trace; do
  timeout 2m java -cp "$TLA_CP" tla2sany.SANY "$m.tla" > "output/trace/sany-$m.log" 2>&1 || { echo "SANY $m failed"; exit 1; }
done
overall=0
for cfg in "${CFGS[@]}"; do
  name="${cfg%.cfg}"
  meta="$STATE_ROOT/trace-$name-$$"
  mkdir -p "$meta"
  timeout 10m java -XX:+UseParallelGC -Xmx8g -cp "$TLA_CP" tlc2.TLC \
      -workers 1 -coverage 1 -metadir "$meta" -config "$cfg" Trace.tla \
      > "output/trace/$name.log" 2>&1
  rc=$?
  rm -rf "$meta"
  if grep -q "Model checking completed. No error has been found" "output/trace/$name.log"; then
    res=PASS
  else
    res=FAIL; overall=1
  fi
  states=$(grep -E "states generated" "output/trace/$name.log" | tail -1)
  echo "$cfg rc=$rc result=$res $states"
done
rmdir "$STATE_ROOT" 2>/dev/null || true
exit $overall
