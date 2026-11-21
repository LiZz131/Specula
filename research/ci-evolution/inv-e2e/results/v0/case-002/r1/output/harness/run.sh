#!/usr/bin/env bash
# Specula incremental harness (rebased from the V0 prior harness).
# Applies the rebased instrumentation patch to a fresh copy of the updated
# artifact tree, builds it, runs the prior regression scenarios plus the
# update-focused scenarios, and writes fresh NDJSON traces.
set -uo pipefail

output_root=/work/current/.specula-output
artifact="$output_root/artifact"
work_source="$output_root/harness/work-source"
trace_root="$output_root/traces"
log_root="$output_root/spec/output/harness"
java_home=/usr/lib/jvm/java-21-openjdk-amd64
mvn_repo=/work/.cache/m2
ledger="$log_root/harness-results.ndjson"
mkdir -p "$trace_root" "$log_root"

if [[ "${SPECULA_REUSE_WORK_SOURCE:-0}" != 1 ]]; then
    rm -rf "$work_source"; mkdir -p "$work_source"
    (cd "$artifact" && tar --exclude=.git -cf - .) | (cd "$work_source" && tar xf -)
    (cd "$work_source" && patch -p1 --no-backup-if-mismatch < "$output_root/harness/patches/instrumentation.patch") \
        > "$log_root/patch-apply.log" 2>&1 || { echo "patch failed"; exit 2; }
fi

(
    cd "$work_source"
    JAVA_HOME="$java_home" timeout 1800s mvn -B -Dmaven.repo.local="$mvn_repo" -pl zookeeper-server -am install \
        -DskipTests -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip
) > "$log_root/build-instrumented.log" 2>&1
build_rc=$?
echo "{\"step\":\"build-instrumented\",\"exit\":$build_rc}" >> "$ledger"
[[ $build_rc -eq 0 ]] || { echo "build failed rc=$build_rc"; exit 3; }

run_case() {
    local scenario="$1" selector="$2" expect="$3"
    local trace="$trace_root/$scenario.ndjson"
    local log="$log_root/harness-$scenario.log"
    [[ -e "$trace" ]] && mv "$trace" "$trace.previous.$$"
    local started; started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    (
        cd "$work_source"
        JAVA_HOME="$java_home" timeout 600s mvn -B -Dmaven.repo.local="$mvn_repo" -pl zookeeper-server \
            -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip \
            -Dspecula.trace.file="$trace" -Dspecula.trace.scenario="$scenario" \
            -Dsurefire.failIfNoSpecifiedTests=false -DfailIfNoTests=false \
            -Dtest="$selector" test
    ) > "$log" 2>&1
    local rc=$?
    local lines=0; [[ -s "$trace" ]] && lines=$(wc -l < "$trace")
    echo "{\"step\":\"scenario\",\"scenario\":\"$scenario\",\"selector\":\"$selector\",\"expected\":\"$expect\",\"exit\":$rc,\"trace\":\"traces/$scenario.ndjson\",\"records\":$lines,\"started\":\"$started\",\"finished\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> "$ledger"
    if [[ ! -s "$trace" ]]; then echo "EMPTY TRACE for $scenario"; return 1; fi
    return 0
}

status=0
# Prior regression scenarios (unchanged selectors)
run_case follower-snap 'Zab1_0Test#testNormalFollowerRun' pass || status=1
run_case follower-diff 'Zab1_0Test#testNormalFollowerRunWithDiff' pass || status=1
run_case quorum-startup-mutation-shutdown 'QuorumPeerMainTest#testQuorum' pass || status=1
run_case leader-abandon-restart-recovery 'QuorumPeerMainTest#testEarlyLeaderAbandonment' pass || status=1
# Update-focused scenarios derived from the visible diff
run_case update-diff-sync-consistency 'DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog' pass || status=1
run_case update-commit-after-newleader 'SpeculaSyncUpdateTest#testCommitOfForwardedProposalAfterNewLeader' observe || status=1
run_case update-newleader-ack-durability 'SpeculaSyncUpdateTest#testNewLeaderAckOnlyAfterDiffTxnDurable' observe || status=1
exit $status
