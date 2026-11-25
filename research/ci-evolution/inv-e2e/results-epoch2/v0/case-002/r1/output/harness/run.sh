#!/usr/bin/env bash
# Rebased Specula harness (incremental run, update revision).
# One command: fresh tree from the artifact's current commit -> apply the
# rebased instrumentation patch -> bounded offline build -> run every prior
# regression scenario plus the update-focused scenario -> fresh NDJSON traces.
#
# Usage: timeout 3600s bash harness/run.sh [scenario ...]
set -euo pipefail

output_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact="$output_root/artifact"
work_source="$output_root/harness/build/work-source"
patch="$output_root/harness/patches/instrumentation.patch"
trace_root="$output_root/traces"
log_root="$output_root/spec/output"
ledger="$log_root/harness-command-results.ndjson"
java_home=/usr/lib/jvm/java-21-openjdk-amd64
mvn_common=(-B -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip=true)

mkdir -p "$trace_root" "$log_root"

prepare_tree() {
    rm -rf "$work_source"
    mkdir -p "$work_source"
    git -C "$artifact" archive HEAD | tar -x -C "$work_source"
    git -C "$artifact" rev-parse HEAD > "$log_root/harness-source-commit.txt"
    (cd "$work_source" && git apply --check "$patch" && git apply "$patch")
    (
        cd "$work_source"
        JAVA_HOME="$java_home" timeout 1200s mvn "${mvn_common[@]}" -pl zookeeper-server -am \
            -DskipTests install
    ) > "$log_root/build-instrumented.log" 2>&1
}

run_case() {
    local scenario="$1"
    local selector="$2"
    local trace="$trace_root/$scenario.ndjson"
    local log="$log_root/harness-$scenario.log"
    local started rc
    rm -f "$trace"
    started="$(date -u +%FT%TZ)"
    set +e
    (
        cd "$work_source"
        JAVA_HOME="$java_home" timeout 600s mvn "${mvn_common[@]}" -pl zookeeper-server \
            -Dspecula.trace.file="$trace" \
            -Dspecula.trace.scenario="$scenario" \
            -Dsurefire.failIfNoSpecifiedTests=false \
            -Dtest="$selector" test
    ) > "$log" 2>&1
    rc=$?
    set -e
    local records=0
    [[ -s "$trace" ]] && records=$(wc -l < "$trace")
    printf '{"scenario":"%s","selector":"%s","started":"%s","finished":"%s","exit_code":%d,"trace":"traces/%s.ndjson","records":%d}\n' \
        "$scenario" "$selector" "$started" "$(date -u +%FT%TZ)" "$rc" "$scenario" "$records" >> "$ledger"
    echo "$scenario exit=$rc records=$records"
}

declare -A SCENARIOS=(
    [follower-snap]='Zab1_0Test#testNormalFollowerRun'
    [follower-diff]='Zab1_0Test#testNormalFollowerRunWithDiff'
    [quorum-startup-mutation-shutdown]='QuorumPeerMainTest#testQuorum'
    [leader-abandon-restart-recovery]='QuorumPeerMainTest#testEarlyLeaderAbandonment'
    [diff-sync-uptodate-failure]='DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog'
)
ORDER=(follower-snap follower-diff quorum-startup-mutation-shutdown
       leader-abandon-restart-recovery diff-sync-uptodate-failure)

if [[ "${SKIP_PREPARE:-0}" != 1 ]]; then
    prepare_tree
fi
selected=("$@")
[[ ${#selected[@]} -eq 0 ]] && selected=("${ORDER[@]}")
for scenario in "${selected[@]}"; do
    run_case "$scenario" "${SCENARIOS[$scenario]}"
done
