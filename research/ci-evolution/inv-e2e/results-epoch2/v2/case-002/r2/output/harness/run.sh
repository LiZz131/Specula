#!/usr/bin/env bash
# Rebased Specular trace harness for the updated ZooKeeper source (case-002).
# Applies harness/patches/instrumentation.patch to a fresh copy of the
# updated artifact (unless SPECULAR_REUSE_WORK_SOURCE=1 and the copy already
# carries the patch), builds it, and runs the selected scenarios, each under
# an outer timeout. Every scenario must produce a fresh nonempty NDJSON trace.
set -euo pipefail

out=/work/current/.specular-output
artifact="$out/artifact"
work_source="$out/harness/work-source"
patch_file="$out/harness/patches/instrumentation.patch"
trace_root="$out/traces"
log_root="$out/spec/output"
java_home=/usr/lib/jvm/java-21-openjdk-amd64
export MAVEN_OPTS="${MAVEN_OPTS:--Dmaven.repo.local=/work/.cache/m2}"

mkdir -p "$trace_root" "$log_root"

prepare() {
    if [[ "${SPECULAR_REUSE_WORK_SOURCE:-0}" == 1 && -d "$work_source/.git" ]] \
       && grep -q SpecularTrace "$work_source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java"; then
        echo "reusing patched work source $work_source"
    else
        rm -rf "$work_source"
        mkdir -p "$work_source"
        rsync -a "$artifact/" "$work_source/"
        (cd "$work_source" && git apply --whitespace=nowarn "$patch_file")
    fi
    (cd "$work_source" && JAVA_HOME="$java_home" timeout 1800s mvn -B -pl zookeeper-server -am \
        -DskipTests -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip install) \
        > "$log_root/build-instrumented.log" 2>&1
}

run_case() {
    local scenario="$1"
    local selector="$2"
    local limit="${3:-400s}"
    local trace="$trace_root/$scenario.ndjson"
    local log="$log_root/harness-$scenario.log"
    rm -f "$trace"
    set +e
    (
        cd "$work_source"
        JAVA_HOME="$java_home" timeout "$limit" mvn -B -pl zookeeper-server \
            -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip \
            -Dspecular.trace.file="$trace" \
            -Dspecular.trace.scenario="$scenario" \
            -Dsurefire.failIfNoSpecifiedTests=false \
            -Dtest="$selector" test
    ) > "$log" 2>&1
    local rc=$?
    set -e
    echo "scenario=$scenario selector=$selector exit=$rc events=$(wc -l < "$trace" 2>/dev/null || echo 0)" | tee -a "$log_root/harness-summary.log"
    test -s "$trace"
}

if [[ "${SPECULAR_SKIP_BUILD:-0}" != 1 ]]; then
    prepare
fi

selected="${SPECULAR_SCENARIOS:-follower-snap follower-diff quorum-startup-mutation-shutdown leader-abandon-restart-recovery diff-sync-uncommitted-log}"
status=0
for s in $selected; do
    case "$s" in
        follower-snap) run_case follower-snap 'Zab1_0Test#testNormalFollowerRun' || status=1 ;;
        follower-diff) run_case follower-diff 'Zab1_0Test#testNormalFollowerRunWithDiff' || status=1 ;;
        quorum-startup-mutation-shutdown) run_case quorum-startup-mutation-shutdown 'QuorumPeerMainTest#testQuorum' || status=1 ;;
        leader-abandon-restart-recovery) run_case leader-abandon-restart-recovery 'QuorumPeerMainTest#testEarlyLeaderAbandonment' || status=1 ;;
        diff-sync-uncommitted-log) run_case diff-sync-uncommitted-log 'DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog' || status=1 ;;
        *) echo "unknown scenario $s"; status=1 ;;
    esac
done
exit $status
