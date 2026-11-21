#!/usr/bin/env bash
# Bounded TLC run. Usage: scripts/mc_run.sh <Module.tla> <cfg> <logname> <bfs|sim> <seconds> <workers> [heapGB] [simdepth]
# - TLC stops itself after <seconds> (-Dtlc2.TLC.stopAfter); an outer `timeout` adds a 10-minute grace.
# - States live under /dev/shm/specula-e2e-case-012/<logname>-<pid> and are removed afterwards.
# - Log: spec/output/<logname>.log (first line = exact command).
set -uo pipefail
spec_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
module="$1"; cfg="$2"; name="$3"; mode="$4"; secs="$5"; workers="$6"; heap="${7:-16}"; depth="${8:-100}"
log="$spec_dir/output/$name.log"
meta="/dev/shm/specula-e2e-case-012/$name-$$"
mkdir -p "$meta"
CP=/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar
extra=()
if [ "$mode" = "sim" ]; then extra=(-simulate num=999999999 -depth "$depth"); fi
cmd=(java -XX:+UseParallelGC -Xmx${heap}g -Dtlc2.TLC.stopAfter=$secs -cp "$CP" tlc2.TLC
     -config "$cfg" -workers "$workers" -metadir "$meta" -cleanup -noGenerateSpecTE -dumpTrace json "$spec_dir/output/$name.trace.json" "${extra[@]}" "$module")
cd "$spec_dir"
echo "# cmd: ${cmd[*]}" > "$log"
timeout $((secs + 600)) "${cmd[@]}" >> "$log" 2>&1
rc=$?
echo "# exit=$rc" >> "$log"
rm -rf "$meta"
summary=$(grep -E "Model checking completed|Invariant .* is violated|Property .* is violated|Temporal properties were violated|Action property|distinct states found|The depth of|Stopped|Error:" "$log" | head -6 | tr '\n' ' ')
echo "$name: rc=$rc $summary"
