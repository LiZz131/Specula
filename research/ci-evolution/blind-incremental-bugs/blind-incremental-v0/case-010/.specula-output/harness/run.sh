#!/usr/bin/env bash
set -euo pipefail

WORK_SOURCE=/work/work-source
OUTPUT=/work/prior/.specula-output
RUN_ID=${SPECULA_TRACE_RUN_ID:-stateful}
TRACE_ONE="$OUTPUT/traces/election-ordered-${RUN_ID}.ndjson"
TRACE_TWO="$OUTPUT/traces/restart-catchup-${RUN_ID}.ndjson"

test "$(git -C "$WORK_SOURCE" rev-parse HEAD)" = "6250c9811a44ed94c825bb5a7cb80fd7b4b883a3"
mkdir -p "$OUTPUT/traces" "$OUTPUT/spec/output"
test ! -e "$TRACE_ONE"
test ! -e "$TRACE_TWO"

COMMON_ARGS=(
  -B -pl zookeeper-server -am
  -Dcheckstyle.skip=true
  -Dspotbugs.skip=true
  -Dmaven.javadoc.skip=true
  -Dsurefire.failIfNoSpecifiedTests=false
)

timeout 15m mvn "${COMMON_ARGS[@]}" \
  -Dtest=SpeculaTraceScenarioTest#testElectionAndOrderedMutations \
  -Dspecula.trace.file="$TRACE_ONE" test \
  > "$OUTPUT/spec/output/harness-election-ordered.log" 2>&1

timeout 15m mvn "${COMMON_ARGS[@]}" \
  -Dtest=SpeculaTraceScenarioTest#testStartupMutationRestartAndCatchup \
  -Dspecula.trace.file="$TRACE_TWO" test \
  > "$OUTPUT/spec/output/harness-restart-catchup.log" 2>&1

test -s "$TRACE_ONE"
test -s "$TRACE_TWO"
