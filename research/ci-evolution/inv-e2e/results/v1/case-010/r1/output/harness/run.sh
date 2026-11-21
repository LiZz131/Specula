#!/usr/bin/env bash
# Rebased Specula harness for the update revision (case-010).
# Usage: SPECULA_TRACE_RUN_ID=<label> [SPECULA_SCENARIOS="a b"] harness/run.sh
set -euo pipefail

OUTPUT=$(cd "$(dirname "$0")/.." && pwd)
ART="$OUTPUT/artifact"
PATCH="$OUTPUT/harness/patches/instrumentation.patch"
RUN_ID=${SPECULA_TRACE_RUN_ID:-v3}
EXPECTED_HEAD=${SPECULA_EXPECTED_HEAD:-b16ba7105238d46b0d51e3cc5d92ce9fe16de834}
LOGDIR="$OUTPUT/spec/output/harness"
mkdir -p "$OUTPUT/traces" "$LOGDIR"

test "$(git -C "$ART" rev-parse HEAD)" = "$EXPECTED_HEAD"

# Apply instrumentation idempotently (tree must be either clean or exactly patched).
if git -C "$ART" apply --reverse --check "$PATCH" 2>/dev/null; then
  echo "instrumentation already applied"
else
  git -C "$ART" apply "$PATCH"
fi

COMMON_ARGS=(
  -B -pl zookeeper-server -am
  -Dcheckstyle.skip=true
  -Dspotbugs.skip=true
  -Dmaven.javadoc.skip=true
  -Drat.skip=true
  -Dsurefire.failIfNoSpecifiedTests=false
)

# name -> test selector (prior regression scenarios first, then update scenarios)
declare -A TESTS=(
  [election-ordered]="SpeculaTraceScenarioTest#testElectionAndOrderedMutations"
  [restart-catchup]="SpeculaTraceScenarioTest#testStartupMutationRestartAndCatchup"
  [upd-snap-exit-diff]="QuorumPeerMainTest#testDiffSyncAfterSnap"
  [upd-serving-exit]="SpeculaTraceScenarioTest#testServingFollowerExitAfterLeaderLoss"
  [upd-snap-complete]="SpeculaTraceScenarioTest#testStartupMutationRestartAndCatchup"
)
# extra JVM properties per scenario (source test knob LearnerHandler.FORCE_SNAP_SYNC)
declare -A EXTRA=(
  [upd-snap-complete]="-Dzookeeper.forceSnapshotSync=true"
)
SCENARIOS=${SPECULA_SCENARIOS:-"election-ordered restart-catchup upd-snap-exit-diff upd-serving-exit upd-snap-complete"}

cd "$ART"
for name in $SCENARIOS; do
  trace="$OUTPUT/traces/${name}-${RUN_ID}.ndjson"
  test ! -e "$trace" || { echo "refusing to overwrite $trace"; exit 2; }
  log="$LOGDIR/${name}-${RUN_ID}.log"
  echo "== $name -> $trace"
  set +e
  timeout 20m mvn "${COMMON_ARGS[@]}" -Dtest="${TESTS[$name]}" ${EXTRA[$name]:-} \
      -Dspecula.trace.file="$trace" test > "$log" 2>&1
  rc=$?
  set -e
  for f in zookeeper-server/target/surefire-reports/*-output.txt; do
    [ -e "$f" ] && cp "$f" "$LOGDIR/${name}-${RUN_ID}.$(basename "$f")"
  done
  echo "$name exit=$rc" | tee -a "$LOGDIR/run-${RUN_ID}.summary"
  grep -E "Tests run:|SPECULA_OBSERVATION|BUILD (SUCCESS|FAILURE)" "$log" | tail -8 || true
  test -s "$trace" || { echo "empty trace: $trace"; exit 3; }
  echo "$name lines=$(wc -l < "$trace")" | tee -a "$LOGDIR/run-${RUN_ID}.summary"
done
