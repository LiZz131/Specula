#!/usr/bin/env bash
# Bounded TLC run: tlc-run.sh <Module> <cfg> <label> <workers> <minutes> [extra TLC args...]
# - graceful budget via -Dtlc2.TLC.stopAfter (TLC prints final statistics),
#   outer `timeout` as a backstop;
# - states under /dev/shm/specular-e2e-case-011/<label>, removed afterwards;
# - log at spec/output/<label>.log, exact command recorded in the log header.
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
module="$1"; cfg="$2"; label="$3"; workers="$4"; minutes="$5"; shift 5
heap="${SPECULAR_TLC_HEAP:-12g}"
state_dir="/dev/shm/specular-e2e-case-011/$label"
log="$suite_root/spec/output/$label.log"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
mkdir -p "$state_dir"
cmd=(timeout "$((minutes + 10))m" java -Xmx"$heap" -XX:+UseParallelGC
     -Dtlc2.TLC.stopAfter=$((minutes * 60)) -cp "$classpath" tlc2.TLC
     -workers "$workers" -metadir "$state_dir" -config "$cfg" "$@" "$module")
cd "$suite_root/spec"
{ echo "# command: (cd spec && ${cmd[*]})"; echo "# started: $(date -u +%FT%TZ)"; } > "$log"
"${cmd[@]}" >> "$log" 2>&1
rc=$?
echo "# exit: $rc finished: $(date -u +%FT%TZ)" >> "$log"
rm -rf "$state_dir"
exit $rc
