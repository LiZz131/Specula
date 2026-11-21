#!/usr/bin/env bash
# Launch a batch of TLC campaigns in parallel and wait for all of them.
# usage: run_campaigns.sh <batch-file>  ; each line: <module> <cfg> <logname> <workers> <stopAfterSec> <heap> [extra args]
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; spec="$root/spec"
pids=()
while read -r mod cfg logname workers stop heap extra; do
  [ -z "${mod:-}" ] && continue; case "$mod" in \#*) continue;; esac
  ( JAVA_OPTS="-Dtlc2.TLC.stopAfter=$stop" TLC_HEAP="$heap" \
      "$root/scripts/tlc.sh" "$spec" "$mod" "$cfg" "$spec/output/$logname.log" $((stop + 600)) \
      -workers "$workers" -deadlock -dumpTrace json "$spec/output/$logname.cex.json" $extra ) &
  pids+=($!)
done < "$1"
for p in "${pids[@]}"; do wait "$p"; done
echo "batch $(basename "$1") done"
