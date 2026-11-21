#!/usr/bin/env bash
# Bounded TLC runner for the case-003 suite.
#   usage: tools/tlc.sh <run-name> <Module.tla> <config.cfg> [extra TLC args...]
#   env:   JSON=<trace path> (trace validation), TLC_TIMEOUT (outer, default 35m),
#          TLC_WORKERS (default 8), TLC_HEAP (default 24g),
#          TLC_STOP_AFTER (seconds; graceful in-JVM budget via -Dtlc2.TLC.stopAfter)
# States live under /dev/shm/specula-e2e-case-003/<run>-<pid> and are removed after
# the run; the log (with the exact command) is spec/output/<run-name>.log.
set -uo pipefail
spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="$1"; shift; module="$1"; shift; cfg="$1"; shift
state_root=/dev/shm/specula-e2e-case-003
meta="$state_root/${name//\//_}-$$"
log="$spec_dir/output/$name.log"
mkdir -p "$state_root" "$(dirname "$log")"
cd "$spec_dir"
cmd=(timeout "${TLC_TIMEOUT:-35m}" java -XX:+UseParallelGC "-Xmx${TLC_HEAP:-24g}" "-DTLA-Library=$spec_dir:$spec_dir/evidence"
     ${TLC_STOP_AFTER:+-Dtlc2.TLC.stopAfter=$TLC_STOP_AFTER}
     -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC
     -config "$cfg" -metadir "$meta" -workers "${TLC_WORKERS:-8}" "$@" "$module")
{ echo "+ cd $spec_dir"; [ -n "${JSON:-}" ] && echo "+ export JSON=$JSON"; echo "+ ${cmd[*]}"; } > "$log"
start=$(date +%s)
"${cmd[@]}" >> "$log" 2>&1
rc=$?
rm -rf "$meta"
# Keep TLC trace-explorer dumps next to the log instead of the spec directory.
ttd="$spec_dir/output/ttrace/${name//\//_}"
for f in "$spec_dir"/*_TTrace_*; do [ -e "$f" ] && mkdir -p "$ttd" && mv "$f" "$ttd/"; done
echo "elapsed_seconds: $(( $(date +%s) - start ))" >> "$log"
echo "exit_code: $rc" >> "$log"
echo "state_dir_removed: $([ -e "$meta" ] && echo no || echo yes)" >> "$log"
exit $rc
