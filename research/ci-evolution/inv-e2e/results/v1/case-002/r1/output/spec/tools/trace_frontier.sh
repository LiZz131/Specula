#!/usr/bin/env bash
# Binary search for the first trace event the spec cannot consume. Run from spec/.
name="$1"; lo=1; hi=$(grep -c "\"tag\":\"trace\"" ../traces/$name.ndjson); hi=$((hi+2))
while [ $((hi-lo)) -gt 1 ]; do
  mid=$(((lo+hi)/2)); meta=/dev/shm/specula-e2e-case-002/frontier-$$-$mid
  out=$(STOP=$mid JSON=../traces/$name.ndjson timeout 600s java -Xmx8g -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -workers 8 -config Trace-progress.cfg -metadir $meta Trace.tla 2>&1)
  rm -rf $meta
  if echo "$out" | grep -q "CursorBelowStop is violated"; then lo=$mid; else hi=$mid; fi
done
echo "$name: cursor reaches $lo; first unconsumed event index = $lo"
