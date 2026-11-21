#!/usr/bin/env bash
# Simulation follow-up: run_sim.sh <batch-file> ; lines: <module> <cfg> <logname> <workers> <stopAfterSec> <heap> <depth>
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"; spec="$root/spec"; pids=()
while read -r mod cfg logname workers stop heap depth; do
  [ -z "${mod:-}" ] && continue; case "$mod" in \#*) continue;; esac
  ( JAVA_OPTS="-Dtlc2.TLC.stopAfter=$stop" TLC_HEAP="$heap" \
      "$root/scripts/tlc.sh" "$spec" "$mod" "$cfg" "$spec/output/$logname.log" $((stop + 600)) \
      -simulate num=999999999 -depth "$depth" -workers "$workers" -deadlock ) &
  pids+=($!)
done < "$1"
for p in "${pids[@]}"; do wait "$p"; done
echo "sim batch $(basename "$1") done"
