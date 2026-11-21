#!/usr/bin/env bash
# MC-1 mechanism reproduction on the new revision (artifact) and the old revision control (artifact-old).
# Expected: new revision FAILS (leaked SyncThread), old revision PASSES.
set -uo pipefail
OUTPUT=$(cd "$(dirname "$0")/.." && pwd)
LOGDIR="$OUTPUT/spec/output/harness"; mkdir -p "$LOGDIR"
ARGS=(-B -pl zookeeper-server -am -Dcheckstyle.skip=true -Dspotbugs.skip=true -Dmaven.javadoc.skip=true -Drat.skip=true -Dsurefire.failIfNoSpecifiedTests=false -Dtest=SpeculaTraceScenarioTest#testServingLearnerExitStopsSyncProcessor)
[ -d "$OUTPUT/artifact-old" ] || git -C "$OUTPUT/artifact" worktree add --detach "$OUTPUT/artifact-old" HEAD~1
for pair in "artifact:instrumentation.patch" "artifact-old:instrumentation-old-control.patch"; do
  t=${pair%%:*}; p="$OUTPUT/harness/patches/${pair##*:}"
  git -C "$OUTPUT/$t" apply --reverse --check "$p" 2>/dev/null || git -C "$OUTPUT/$t" apply "$p"
done
for tree in artifact artifact-old; do
  ( cd "$OUTPUT/$tree" && timeout 20m mvn "${ARGS[@]}" test > "$LOGDIR/repro-mc1-$tree.log" 2>&1; echo "$tree exit=$?" | tee -a "$LOGDIR/repro-mc1.summary" )
  grep -E "Tests run:|AssertionFailedError|expected" "$LOGDIR/repro-mc1-$tree.log" | head -4 | tee -a "$LOGDIR/repro-mc1.summary"
  cp "$OUTPUT/$tree/zookeeper-server/target/surefire-reports/org.apache.zookeeper.server.quorum.SpeculaTraceScenarioTest-output.txt" "$LOGDIR/repro-mc1-$tree.surefire-output.txt" 2>/dev/null || true
done
