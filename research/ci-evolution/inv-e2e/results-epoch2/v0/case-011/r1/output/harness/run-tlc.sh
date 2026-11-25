#!/usr/bin/env bash
# Bounded TLC run. Usage: run-tlc.sh <run-name> <module> <cfg> <workers> <minutes> [extra TLC args...]
# States live under /dev/shm/specula-e2e-case-011/<run-name>-<pid> and are removed afterwards.
# Log: spec/output/<run-name>.log (first lines record the exact command).
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="$1"; module="$2"; cfg="$3"; workers="$4"; minutes="$5"; shift 5
state="/dev/shm/specula-e2e-case-011/$name-$$"
log="$suite_root/spec/output/$name.log"
mkdir -p "$state"
cd "$suite_root/spec"
cmd=(java -XX:+UseParallelGC -Xmx${TLC_XMX:-12g} -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar
     tlc2.TLC -workers "$workers" -metadir "$state" -config "$cfg" "$@" "$module")
{ echo "# run: $name  started: $(date -Is)"; echo "# timeout ${minutes}m: ${cmd[*]}"; } > "$log"
timeout --signal=TERM "${minutes}m" "${cmd[@]}" >> "$log" 2>&1
rc=$?
echo "# exit code: $rc ($( [ $rc -eq 124 ] && echo 'outer time budget reached' || echo 'TLC terminated'))  finished: $(date -Is)" >> "$log"
rm -rf "$state"
exit $rc
