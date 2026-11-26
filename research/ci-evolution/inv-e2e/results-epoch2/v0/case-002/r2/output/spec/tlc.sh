#!/usr/bin/env bash
# Bounded TLC runner for this run.  Usage:
#   tlc.sh <name> <spec.tla> <cfg> <outer-timeout> [extra TLC args...]
# States live below /dev/shm/specular-e2e-case-002/<name> and are removed
# after the run; the log is spec/output/<name>.log.
set -u
name="$1"; spec="$2"; cfg="$3"; otimeout="$4"; shift 4
here="$(cd "$(dirname "$0")" && pwd)"
lib=/work/lib
state=/dev/shm/specular-e2e-case-002/"$name"
log="$here/output/$name.log"
mkdir -p "$here/output" /dev/shm/specular-e2e-case-002
rm -rf "$state"
cd "$here"
{
  echo "# command: timeout $otimeout java -XX:+UseParallelGC -Xmx${TLC_HEAP:-24g} -cp $lib/tla2tools.jar:$lib/CommunityModules-deps.jar tlc2.TLC -config $cfg -metadir $state -cleanup $* $spec"
  echo "# started: $(date -u +%FT%TZ)"
} > "$log"
timeout "$otimeout" java -XX:+UseParallelGC -Xmx${TLC_HEAP:-24g} \
  -Dtlc2.tool.fp.FPSet.impl=tlc2.tool.fp.OffHeapDiskFPSet \
  -cp "$lib/tla2tools.jar:$lib/CommunityModules-deps.jar" tlc2.TLC \
  -config "$cfg" -metadir "$state" -cleanup "$@" "$spec" >> "$log" 2>&1
rc=$?
echo "# exit: $rc  finished: $(date -u +%FT%TZ)" >> "$log"
rm -rf "$state"
exit $rc
