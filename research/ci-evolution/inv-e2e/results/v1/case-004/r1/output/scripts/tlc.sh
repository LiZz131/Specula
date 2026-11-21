#!/usr/bin/env bash
# Bounded TLC runner. usage: tlc.sh <workdir> <module.tla> <config.cfg> <logfile> <outer-timeout> [extra TLC args...]
# TLC state goes below /dev/shm/specula-e2e-case-004/ and is removed after the run.
set -u
wd="$1"; mod="$2"; cfg="$3"; log="$4"; to="$5"; shift 5
run_id="$(basename "$cfg" .cfg)-$(date +%s%N)"
meta="/dev/shm/specula-e2e-case-004/$run_id"
mkdir -p "$meta"
cd "$wd"
echo "# cmd: timeout $to java ${JAVA_OPTS:-} -XX:+UseParallelGC -Xmx${TLC_HEAP:-24g} -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -metadir $meta -config $cfg $* $mod" > "$log"
echo "# cwd: $wd" >> "$log"
echo "# start: $(date -Is)" >> "$log"
timeout "$to" java ${JAVA_OPTS:-} -XX:+UseParallelGC -Xmx${TLC_HEAP:-24g} -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar \
    tlc2.TLC -metadir "$meta" -config "$cfg" "$@" "$mod" >> "$log" 2>&1
rc=$?
echo "# exit: $rc end: $(date -Is)" >> "$log"
rm -rf "$meta"
exit $rc
