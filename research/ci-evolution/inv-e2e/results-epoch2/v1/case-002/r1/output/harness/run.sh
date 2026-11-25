#!/usr/bin/env bash
# Incremental (V1) trace harness: rebased from the V0 prior harness.
# One command: prepare instrumented copy of the updated source, build, run scenarios,
# write fresh NDJSON traces.  Every Maven step is bounded by an outer timeout.
set -uo pipefail

out=/work/current/.specula-output
artifact="$out/artifact"
work_source="$out/harness/work-source"
patch="$out/harness/patches/instrumentation.patch"
trace_root="$out/traces"
log_root="$out/spec/output/incremental/harness"
java_home=/usr/lib/jvm/java-11-openjdk-amd64
repo=/work/.cache/m2
mkdir -p "$trace_root" "$log_root"

if [[ "${SKIP_PREPARE:-0}" != 1 ]]; then
    rm -rf "$work_source"
    mkdir -p "$work_source"
    cp -a "$artifact/." "$work_source/"
    (cd "$work_source" && git apply "$patch") || { echo "patch failed" >&2; exit 2; }
    (cd "$work_source" && JAVA_HOME="$java_home" timeout 2400s mvn -B -pl zookeeper-server -am install \
        -DskipTests -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip \
        -Dmaven.repo.local="$repo") > "$log_root/build.log" 2>&1 || { echo "build failed" >&2; exit 3; }
fi

status=0
run_case() {
    local scenario="$1" selector="$2" budget="${3:-300s}"
    local trace="$trace_root/$scenario.ndjson"
    # fault-injected reproduction traces are kept out of the conformance suite
    case "$scenario" in
        repro-u1-*) mkdir -p "$trace_root/fault-injected-repro"; trace="$trace_root/fault-injected-repro/$scenario.ndjson" ;;
        repro-u3-*) mkdir -p "$trace_root/fault-injected-repro"; trace="$trace_root/fault-injected-repro/$scenario.ndjson" ;;
        follower-diff-bigdiff-*) mkdir -p "$trace_root/observation-only"; trace="$trace_root/observation-only/$scenario.ndjson" ;;
    esac
    local log="$log_root/$scenario.log"
    rm -f "$trace"
    (
        cd "$work_source"
        JAVA_HOME="$java_home" timeout "$budget" mvn -B -pl zookeeper-server \
            -Dmaven.repo.local="$repo" \
            -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip \
            -Dspecula.trace.file="$trace" \
            -Dspecula.trace.scenario="$scenario" \
            -Dspecula.diff.txns="${DIFF_TXNS:-7}" \
            -Dtest="$selector" -DfailIfNoTests=false test
    ) > "$log" 2>&1
    local rc=$?
    local n=0; [[ -s "$trace" ]] && n=$(wc -l < "$trace")
    echo "$scenario rc=$rc events=$n" | tee -a "$log_root/summary.txt"
    [[ $rc -eq 0 && $n -gt 0 ]] || status=1
}

: > "$log_root/summary.txt"
SCENARIOS="${SCENARIOS:-follower-snap follower-diff quorum-startup-mutation-shutdown leader-abandon-restart-recovery diff-sync-uptodate-failure follower-diff-bulk-r1 follower-diff-bulk-r2 follower-diff-bulk-r3 repro-u4-no-restart-r1 repro-u4-no-restart-r2 repro-u4-no-restart-r3 control-diffsync-leaderwait-r1 control-diffsync-leaderwait-r2 repro-u1-stalled-log-r1 repro-u1-stalled-log-r2 repro-u1-stalled-log-r3}"
for s in $SCENARIOS; do
    case "$s" in
        follower-snap) run_case follower-snap 'Zab1_0Test#testNormalFollowerRun' ;;
        follower-diff) run_case follower-diff 'Zab1_0Test#testNormalFollowerRunWithDiff' ;;
        quorum-startup-mutation-shutdown) run_case quorum-startup-mutation-shutdown 'QuorumPeerMainTest#testQuorum' ;;
        leader-abandon-restart-recovery) run_case leader-abandon-restart-recovery 'QuorumPeerMainTest#testEarlyLeaderAbandonment' ;;
        diff-sync-uptodate-failure) run_case diff-sync-uptodate-failure 'DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog' 400s ;;
        follower-diff-r*) run_case "$s" 'Zab1_0Test#testNormalFollowerRunWithDiff' ;;
        control-diffsync-leaderwait*) run_case "$s" 'SpeculaDiffSyncControlTest#testUpdateScenarioWithLeaderWait' 600s ;;
        repro-u1-stalled-log*) run_case "$s" 'SpeculaU1ReproTest#testNewLeaderAckBeforeDurableThenRestart' 600s ;;
        repro-u4-no-restart*) run_case "$s" 'SpeculaU4ReproTest#testNoRestartAfterUptodateFailure' 600s ;;
        repro-u3-ack-delay*) run_case "$s" 'SpeculaU3ReproTest#testTxnAckBeforeNewLeaderAck' 600s ;;
        follower-diff-bigdiff-r*) DIFF_TXNS=${DIFF_TXNS:-1500} run_case "$s" 'SpeculaNewLeaderAckOrderTest#testFirstAckAfterNewLeaderWithDiff' ;;
        follower-diff-bulk-r*) run_case "$s" 'SpeculaNewLeaderAckOrderTest#testFirstAckAfterNewLeaderWithDiff' ;;
        *) echo "unknown scenario $s" >&2; status=1 ;;
    esac
done
exit $status
