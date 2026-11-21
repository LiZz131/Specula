#!/usr/bin/env bash
# Rebased case-010 harness: exact V0 probes + incremental update probes on the
# updated artifact (commit "update"), prior regression scenarios, and the update
# scenario QuorumPeerMainTest#testDiffSyncAfterSnap supplied by the source diff.
set -euo pipefail
OUTPUT=/work/current/.specula-output
ART="$OUTPUT/artifact"
RUN_ID=${SPECULA_TRACE_RUN_ID:-new}
SCENARIOS=${SPECULA_SCENARIOS:-"election-ordered restart-catchup diff-sync-after-snap snap-complete"}
EXPECTED_HEAD=b16ba7105238d46b0d51e3cc5d92ce9fe16de834

test "$(git -C "$ART" rev-parse HEAD)" = "$EXPECTED_HEAD"
mkdir -p "$OUTPUT/traces" "$OUTPUT/spec/output/harness"

# Re-apply instrumentation from a clean tree (idempotent).
git -C "$ART" checkout -- zookeeper-server/src
rm -f "$ART/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/SpeculaTrace.java" \
      "$ART/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/SpeculaTraceScenarioTest.java"
git -C "$ART" apply "$OUTPUT/harness/patches/instrumentation-v0.patch"
python3 -I "$OUTPUT/harness/apply_update_probes.py" "$ART" new

COMMON_ARGS=(-B -pl zookeeper-server -am -Dcheckstyle.skip=true -Dspotbugs.skip=true
  -Dmaven.javadoc.skip=true -Dsurefire.failIfNoSpecifiedTests=false -DfailIfNoTests=false)

run_one() {  # name test-selector
  local name=$1 sel=$2 trace="$OUTPUT/traces/$1-$RUN_ID.ndjson"
  test ! -e "$trace" || { echo "refusing to overwrite $trace" >&2; return 1; }
  local rc=0
  ( cd "$ART" && timeout 15m mvn "${COMMON_ARGS[@]}" -Dtest="$sel" \
      -Dspecula.trace.file="$trace" test ) \
      > "$OUTPUT/spec/output/harness/$name-$RUN_ID.log" 2>&1 || rc=$?
  echo "$name rc=$rc lines=$(wc -l < "$trace" 2>/dev/null || echo 0)"
  test -s "$trace"
  return $rc
}

for s in $SCENARIOS; do
  case $s in
    election-ordered) run_one $s 'SpeculaTraceScenarioTest#testElectionAndOrderedMutations' ;;
    restart-catchup)  run_one $s 'SpeculaTraceScenarioTest#testStartupMutationRestartAndCatchup' ;;
    diff-sync-after-snap) run_one $s 'QuorumPeerMainTest#testDiffSyncAfterSnap' ;;
    snap-complete)    run_one $s 'SpeculaTraceScenarioTest#testForcedSnapSyncCompletes' ;;
    *) echo "unknown scenario $s" >&2; exit 2 ;;
  esac
done
