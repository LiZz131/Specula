#!/usr/bin/env bash
# Rebased Specula harness for the UPDATED source (neutral commit "update").
# One command: verify source identity, (re)apply instrumentation, build,
# run the prior regression scenarios and the update scenario, write fresh
# NDJSON traces, fail unless every trace is nonempty.
set -euo pipefail

OUTPUT=/work/current/.specula-output
WORK_SOURCE=$OUTPUT/artifact
UPDATE_SHA=b16ba7105238d46b0d51e3cc5d92ce9fe16de834
RUN_ID=${SPECULA_TRACE_RUN_ID:-v3}
LOGDIR=$OUTPUT/spec/output
TRACES=$OUTPUT/traces
PATCH=$OUTPUT/harness/patches/instrumentation.patch

test "$(git -C "$WORK_SOURCE" rev-parse HEAD)" = "$UPDATE_SHA"
mkdir -p "$TRACES" "$LOGDIR"

# Re-apply instrumentation from a clean update tree (idempotent).
git -C "$WORK_SOURCE" checkout -- .
rm -f "$WORK_SOURCE"/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/SpeculaTrace.java \
      "$WORK_SOURCE"/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/SpeculaTraceScenarioTest.java
git -C "$WORK_SOURCE" apply "$PATCH"

COMMON_ARGS=(
  -B -pl zookeeper-server
  -Dcheckstyle.skip=true
  -Dspotbugs.skip=true
  -Dmaven.javadoc.skip=true
  -Drat.skip=true
  -Dsurefire.failIfNoSpecifiedTests=false
)

cd "$WORK_SOURCE"
timeout 15m mvn "${COMMON_ARGS[@]}" test-compile > "$LOGDIR/harness-build-${RUN_ID}.log" 2>&1

run_scenario() {   # name  test-selector
  local name=$1 sel=$2
  local trace="$TRACES/${name}-${RUN_ID}.ndjson"
  test ! -e "$trace"
  timeout 15m mvn "${COMMON_ARGS[@]}" -Dtest="$sel" -Dspecula.trace.file="$trace" test \
    > "$LOGDIR/harness-${name}-${RUN_ID}.log" 2>&1
  test -s "$trace"
  echo "$name: $(wc -l < "$trace") events -> $trace"
}

# Prior regression scenarios (unchanged test driver from the V0 harness).
run_scenario election-ordered  'SpeculaTraceScenarioTest#testElectionAndOrderedMutations'
run_scenario restart-catchup   'SpeculaTraceScenarioTest#testStartupMutationRestartAndCatchup'
# Update scenario: the test added by the update itself (visible diff).
run_scenario snap-abort-rejoin 'QuorumPeerMainTest#testDiffSyncAfterSnap'
# Update-derived scenario: same forced-SNAP path, sync completes (NEWLEADER snapshot), restart.
run_scenario snap-complete-restart 'SpeculaTraceScenarioTest#testForcedSnapRejoinCompletesAndRestarts'
