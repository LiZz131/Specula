#!/usr/bin/env bash
# Bounded TLC runner for the V1 incremental run.
# usage: tools/run_tlc.sh <log-name> <SPEC.tla> <CFG.cfg> [extra TLC args...]
# env:   TLC_OUTER_TIMEOUT (default 40m), TLC_HEAP (default 24g), TLC_JVM_OPTS,
#        JSON=<trace file> for Trace.tla (read through IOEnv).
# - states live below /dev/shm/specula-e2e-case-003/<name>-<pid> and are
#   removed after the run;
# - the full command, timestamps and exit code are written into
#   spec/output/<log-name>.log;
# - counterexamples are dumped as spec/output/<log-name>.cex.json.
set -u
spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="$1"; spec="$2"; cfg="$3"; shift 3
state_root=/dev/shm/specula-e2e-case-003
meta="$state_root/${name}-$$-$(date +%s%N)"
log="$spec_dir/output/${name}.log"
cex="$spec_dir/output/${name}.cex.json"
mkdir -p "$meta" "$spec_dir/output"
rm -f "$cex"
cmd=(timeout --kill-after=60s "${TLC_OUTER_TIMEOUT:-40m}" java -XX:+UseParallelGC "-Xmx${TLC_HEAP:-24g}" ${TLC_JVM_OPTS:-}
     -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar
     tlc2.TLC -metadir "$meta" -noGenerateSpecTE -dumpTrace json "$cex"
     -config "$cfg" "$@" "$spec")
{
  echo "# cwd: $spec_dir"
  [ -n "${JSON:-}" ] && echo "# env: JSON=$JSON"
  echo "# command: ${cmd[*]}"
  echo "# started: $(date -Is)"
} > "$log"
(cd "$spec_dir" && "${cmd[@]}") >> "$log" 2>&1
rc=$?
{
  echo "# exit: $rc"
  echo "# finished: $(date -Is)"
} >> "$log"
rm -rf "$meta"
[ -d "$meta" ] && echo "WARNING: state dir not removed: $meta" >&2
echo "$name exit=$rc log=output/${name}.log"
exit $rc
