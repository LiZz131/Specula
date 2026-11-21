#!/usr/bin/env bash
# Old-revision control (attribution only): same probes and scenarios on the
# exact-old source (artifact commit `baseline`), with the update's new test file
# copied in (test-only). Usage: harness/run-old-control.sh
set -euo pipefail
OUTPUT=$(cd "$(dirname "$0")/.." && pwd)
ART="$OUTPUT/artifact-old"
PATCH="$OUTPUT/harness/patches/instrumentation-old-control.patch"
RUN_ID=${SPECULA_TRACE_RUN_ID:-oldctl}
LOGDIR="$OUTPUT/spec/output/harness"
mkdir -p "$OUTPUT/traces/old-control" "$LOGDIR"
[ -d "$ART" ] || git -C "$OUTPUT/artifact" worktree add --detach "$ART" HEAD~1
test "$(git -C "$ART" rev-parse HEAD)" = "$(git -C "$OUTPUT/artifact" rev-parse HEAD~1)"
git -C "$ART" apply --reverse --check "$PATCH" 2>/dev/null || git -C "$ART" apply "$PATCH"
COMMON_ARGS=(-B -pl zookeeper-server -am -Dcheckstyle.skip=true -Dspotbugs.skip=true -Dmaven.javadoc.skip=true -Drat.skip=true -Dsurefire.failIfNoSpecifiedTests=false)
declare -A TESTS=(
  [upd-snap-exit-diff]="QuorumPeerMainTest#testDiffSyncAfterSnap"
  [upd-serving-exit]="SpeculaTraceScenarioTest#testServingFollowerExitAfterLeaderLoss"
)
cd "$ART"
for name in upd-snap-exit-diff upd-serving-exit; do
  trace="$OUTPUT/traces/old-control/${name}-${RUN_ID}.ndjson"
  log="$LOGDIR/old-control-${name}-${RUN_ID}.log"
  rm -f "$trace"
  set +e
  timeout 20m mvn "${COMMON_ARGS[@]}" -Dtest="${TESTS[$name]}" -Dspecula.trace.file="$trace" test > "$log" 2>&1
  rc=$?
  set -e
  echo "$name exit=$rc" | tee -a "$LOGDIR/old-control-${RUN_ID}.summary"
  grep -E "Tests run:|FAIL|should exist|AssertionFailedError" "$log" | head -6 | tee -a "$LOGDIR/old-control-${RUN_ID}.summary" || true
  cp zookeeper-server/target/surefire-reports/*-output.txt "$LOGDIR/" 2>/dev/null || true
  for f in zookeeper-server/target/surefire-reports/*-output.txt; do cp "$f" "$LOGDIR/old-control-${name}-$(basename "$f")"; done 2>/dev/null || true
done
