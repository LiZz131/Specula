#!/usr/bin/env bash
# Rebased Specula harness for the UPDATED source (artifact commit "update").
# Applies the instrumentation patch (if not already applied), builds, runs the
# prior regression scenarios plus the update-focused scenarios, and writes fresh
# NDJSON traces under ../traces.  Every Maven invocation is bounded.
set -euo pipefail

output_root=/work/current/.specula-output
work_source="$output_root/artifact"
trace_root="$output_root/traces"
log_root="$output_root/spec/output/update"
patch="$output_root/harness/patches/instrumentation.patch"
java_home=/usr/lib/jvm/java-21-openjdk-amd64
export MAVEN_OPTS="${MAVEN_OPTS:--Dmaven.repo.local=/work/.cache/m2}"

mkdir -p "$trace_root" "$log_root"

cd "$work_source"
if ! grep -q 'class SpeculaTrace' zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/SpeculaTrace.java 2>/dev/null; then
    git apply "$patch"
fi

if [[ "${SKIP_BUILD:-0}" != 1 ]]; then
    JAVA_HOME="$java_home" timeout 1500s mvn -B -pl zookeeper-server -am install -DskipTests \
        -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip \
        > "$log_root/build-instrumented.log" 2>&1
fi

run_case() {
    local scenario="$1"
    local selector="$2"
    local limit="${3:-300s}"
    local trace="$trace_root/$scenario.ndjson"
    local log="$log_root/harness-$scenario.log"
    rm -f "$trace"
    set +e
    (
        cd "$work_source"
        JAVA_HOME="$java_home" timeout "$limit" mvn -B -pl zookeeper-server \
            -Dmaven.javadoc.skip=true \
            -Dcheckstyle.skip -Dspotbugs.skip \
            -Dspecula.trace.file="$trace" \
            -Dspecula.trace.scenario="$scenario" \
            -DfailIfNoTests=false \
            -Dtest="$selector" test
    ) > "$log" 2>&1
    local rc=$?
    set -e
    echo "$scenario exit=$rc records=$( [[ -s $trace ]] && wc -l < "$trace" || echo 0)" | tee -a "$log_root/harness-summary.txt"
}

: > "$log_root/harness-summary.txt"
# Prior regression scenarios (rerun on the updated implementation).
run_case follower-snap 'Zab1_0Test#testNormalFollowerRun'
run_case follower-diff 'Zab1_0Test#testNormalFollowerRunWithDiff'
run_case quorum-startup-mutation-shutdown 'QuorumPeerMainTest#testQuorum'
run_case leader-abandon-restart-recovery 'QuorumPeerMainTest#testEarlyLeaderAbandonment'
# Update-focused scenarios (derived from the visible diff).
run_case update-diff-sync-consistency 'DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog' 400s
if [[ "${RUN_OBSERVATIONS:-1}" == 1 ]]; then
    run_case update-observe-ack-durability 'SpeculaUpdateObservationTest#newLeaderAckPrecedesDurability'
    run_case update-observe-commit-after-newleader 'SpeculaUpdateObservationTest#commitOfStreamedProposalAfterNewLeader'
fi
