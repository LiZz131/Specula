#!/usr/bin/env bash
# Old-implementation control: exact-old main code (commit "baseline") + the same
# probes (old Learner.shutdown variant) + the update's test file, running the
# diff's own scenario QuorumPeerMainTest#testDiffSyncAfterSnap.
set -euo pipefail
OUTPUT=/work/current/.specula-output
ART="$OUTPUT/artifact"; OLD="$OUTPUT/work-old"
BASE=f8533cdd2177479d5792649efc05e78abc8cb802
TRACE="$OUTPUT/traces/diff-sync-after-snap-oldcontrol.ndjson"
test ! -e "$TRACE"
if [ ! -d "$OLD" ]; then git -C "$ART" worktree add --detach "$OLD" "$BASE"; fi
test "$(git -C "$OLD" rev-parse HEAD)" = "$BASE"
git -C "$OLD" checkout -- zookeeper-server/src
rm -f "$OLD/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/SpeculaTrace.java" \
      "$OLD/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/SpeculaTraceScenarioTest.java"
git -C "$OLD" apply "$OUTPUT/harness/patches/instrumentation-v0.patch"
python3 -I "$OUTPUT/harness/apply_update_probes.py" "$OLD" old
git -C "$ART" show "update:zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/QuorumPeerMainTest.java" \
  > "$OLD/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/QuorumPeerMainTest.java" 2>/dev/null || \
git -C "$ART" show "b16ba7105238d46b0d51e3cc5d92ce9fe16de834:zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/QuorumPeerMainTest.java" \
  > "$OLD/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/QuorumPeerMainTest.java"
rc=0
( cd "$OLD" && timeout 15m mvn -B -pl zookeeper-server -am -Dcheckstyle.skip=true -Dspotbugs.skip=true \
    -Dmaven.javadoc.skip=true -Dsurefire.failIfNoSpecifiedTests=false -DfailIfNoTests=false \
    -Dtest='QuorumPeerMainTest#testDiffSyncAfterSnap' -Dspecula.trace.file="$TRACE" test ) \
  > "$OUTPUT/spec/output/harness/diff-sync-after-snap-oldcontrol.log" 2>&1 || rc=$?
echo "oldcontrol rc=$rc lines=$(wc -l < "$TRACE")"
