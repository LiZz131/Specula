#!/usr/bin/env bash
# usage: run_wave.sh <label> "<cfg:module:min:workers:label> ..."
cd "$(dirname "$0")"
wave=$1; shift
for spec in $1; do
  IFS=: read cfg mod mins w label <<< "$spec"
  XMX=${XMX:-10g} ./run_tlc.sh "$cfg" "$mod" "$mins" "$w" "$label" &
done
wait
echo "WAVE $wave DONE"
