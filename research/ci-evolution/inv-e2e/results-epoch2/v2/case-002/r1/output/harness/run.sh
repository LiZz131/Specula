#!/usr/bin/env bash
# One-command harness for case-002 (revision `update`): reset the writable
# copy of the updated tree, apply the rebased instrumentation, build, run the
# prior regression scenarios plus the update-focused scenarios, and collect
# fresh NDJSON traces.  Every Maven invocation has an outer timeout.
set -euo pipefail

output_root=/work/current/.specula-output
work_source="$output_root/work-source"
trace_root="$output_root/traces"
log_root="$output_root/spec/output/harness"
patch="$output_root/harness/patches/instrumentation.patch"
export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}
export MAVEN_OPTS="${MAVEN_OPTS:--Dmaven.repo.local=/work/.cache/m2}"
mvn_flags=(-B -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip)

mkdir -p "$trace_root" "$log_root"

if [[ "${SKIP_APPLY:-0}" != 1 ]]; then
    (
        cd "$work_source"
        git checkout -q -- .
        rm -f zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/SpeculaTrace.java
        git apply "$patch"
        git status --short
    ) 2>&1 | tee "$log_root/apply.log"
    (
        cd "$work_source"
        timeout 1200s mvn "${mvn_flags[@]}" -DskipTests -pl zookeeper-server -am install
    ) > "$log_root/build-instrumented.log" 2>&1
fi

run_case() {
    local scenario="$1"
    local selector="$2"
    local limit="${3:-420s}"
    local trace="$trace_root/$scenario.ndjson"
    local log="$log_root/harness-$scenario.log"
    if [[ -e "$trace" ]]; then
        mv "$trace" "$trace.superseded.$(date +%s)"
    fi
    local status=0
    (
        cd "$work_source"
        timeout "$limit" mvn "${mvn_flags[@]}" -pl zookeeper-server \
            -Dspecula.trace.file="$trace" \
            -Dspecula.trace.scenario="${SCENARIO_LABEL:-$scenario}" \
            -Dtest="$selector" -DfailIfNoTests=false test
    ) > "$log" 2>&1 || status=$?
    local records=0
    [[ -s "$trace" ]] && records=$(wc -l < "$trace")
    printf '%s\t%s\texit=%s\trecords=%s\n' "$scenario" "$selector" "$status" "$records" \
        | tee -a "$log_root/run-summary.tsv"
    test -s "$trace"
}

cases=("$@")
if [[ ${#cases[@]} -eq 0 ]]; then
    cases=(follower-snap follower-diff quorum-startup-mutation-shutdown
           leader-abandon-restart-recovery diff-sync-uncommitted-log)
fi
rc=0
for c in "${cases[@]}"; do
    case "$c" in
        follower-snap) run_case "$c" 'Zab1_0Test#testNormalFollowerRun' || rc=1 ;;
        follower-diff) run_case "$c" 'Zab1_0Test#testNormalFollowerRunWithDiff' || rc=1 ;;
        quorum-startup-mutation-shutdown) run_case "$c" 'QuorumPeerMainTest#testQuorum' || rc=1 ;;
        leader-abandon-restart-recovery) run_case "$c" 'QuorumPeerMainTest#testEarlyLeaderAbandonment' || rc=1 ;;
        diff-sync-uncommitted-log) run_case "$c" 'DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog' 600s || rc=1 ;;
        follower-diff-repeat-*) SCENARIO_LABEL=follower-diff run_case "$c" 'Zab1_0Test#testNormalFollowerRunWithDiff' || rc=1 ;;
        *) echo "unknown scenario $c" >&2; rc=1 ;;
    esac
done
exit "$rc"
