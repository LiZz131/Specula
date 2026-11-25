#!/usr/bin/env bash
# Bounded TLC campaign runner.
# usage: run-model-check.sh <run-name> <Module> <cfg> [extra TLC args...]
# env: SPECULA_MC_SECONDS (TLC stopAfter budget, default 1800),
#      SPECULA_MC_WORKERS (default 8), SPECULA_MC_HEAP (default 24g)
# States live under /dev/shm/specula-e2e-case-011/<run>-<pid> and are removed
# after the run. The log header records the exact command. A run that stops
# on its time budget with states left on the queue is LIMITED_COVERAGE.
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
name="$1"; module="$2"; cfg="$3"; shift 3
secs="${SPECULA_MC_SECONDS:-1800}"
workers="${SPECULA_MC_WORKERS:-8}"
heap="${SPECULA_MC_HEAP:-24g}"
classpath="/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
state_dir="/dev/shm/specula-e2e-case-011/${name}-$$"
log="$suite_root/spec/output/mc-$name.log"
cex="$suite_root/spec/output/mc-$name.cex.json"
mkdir -p "$state_dir"
cd "$suite_root/spec"
cmd=(java -Dtlc2.TLC.stopAfter="$secs" -XX:+UseParallelGC -Xmx"$heap" -cp "$classpath" tlc2.TLC -noGenerateSpecTE
     -workers "$workers" -metadir "$state_dir" -dumpTrace json "$cex" -config "$cfg" "$@" "$module")
{ echo "# run: $name"; echo "# date: $(date -Is)"; echo "# cwd: $PWD"; echo "# cmd: ${cmd[*]}"; } > "$log"
timeout $((secs + 600)) "${cmd[@]}" >> "$log" 2>&1
rc=$?
rm -rf "${state_dir:?}"
left=$(grep -oE '[0-9]+ states left on queue' "$log" | tail -1 | grep -oE '^[0-9]+')
if grep -qE "is violated" "$log"; then verdict="VIOLATION"
elif grep -qE "^Error:" "$log"; then verdict="TLC_ERROR"
elif [ -n "$left" ] && [ "$left" != "0" ]; then verdict="LIMITED_COVERAGE(queue=$left)"
elif grep -q 'Model checking completed. No error has been found.' "$log"; then verdict="EXHAUSTED_NO_VIOLATION"
elif grep -q -- "-simulate" "$log" && [ "$rc" -eq 0 ]; then verdict="SIMULATION_BUDGET_EXHAUSTED_NO_VIOLATION"
else verdict="INCOMPLETE(rc=$rc)"; fi
echo "# verdict: $verdict (tlc rc=$rc)" >> "$log"
echo "$name: $verdict"
