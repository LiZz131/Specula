#!/usr/bin/env bash
# Replays every retained fresh new-version trace against Trace.tla with real
# TLC (TraceMatched temporal property + invariants).  Usage:
#   run-trace-validation.sh <round-label> [cfg] [trace ...]
set -uo pipefail
cd /work/current/.specular-output/spec
label="${1:?round label}"; shift
cfg="${1:-Trace.cfg}"; shift || true
traces=("$@")
if [[ ${#traces[@]} -eq 0 ]]; then traces=(../traces/*.ndjson); fi
outdir=output/trace-validation/$label
mkdir -p "$outdir"
states=/dev/shm/specular-e2e-case-002/trace-$label
for t in "${traces[@]}"; do
  name=$(basename "$t" .ndjson)
  log="$outdir/$name.log"
  meta="$states/$name"
  mkdir -p "$meta"
  spec_file="${SPEC_FILE:-Trace.tla}"; cmd="timeout 900s env JSON=$t java -Xmx8g -XX:+UseParallelGC -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -cleanup -workers 4 -config $cfg -metadir $meta $spec_file"
  start=$(date -u +%FT%TZ)
  bash -c "$cmd" > "$log" 2>&1
  rc=$?
  rm -rf "$meta"
  events=$(wc -l < "$t")
  ok=$(grep -c "Model checking completed. No error has been found." "$log")
  echo "{\"round\":\"$label\",\"trace\":\"traces/$name.ndjson\",\"events\":$events,\"cfg\":\"$cfg\",\"command\":\"cd spec && $cmd\",\"log\":\"spec/$log\",\"started_at_utc\":\"$start\",\"exit_code\":$rc,\"no_error\":$ok}" | tee -a output/trace-validation/command-results.ndjson
done
rm -rf "$states"
