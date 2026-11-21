#!/usr/bin/env bash
# Rebased Specula harness (incremental run, updated source).
# One command: apply instrumentation to the updated artifact, build, run the
# prior regression scenarios plus the update-focused scenario, collect traces.
set -euo pipefail

output_root=/work/current/.specula-output
work_source="$output_root/artifact"
trace_root="$output_root/traces"
log_root="$output_root/spec/output"
patch="$output_root/harness/patches/instrumentation.patch"
java_home=/usr/lib/jvm/java-21-openjdk-amd64
mvn_flags=(-B -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip=true)

mkdir -p "$trace_root" "$log_root"

apply_instrumentation() {
    cd "$work_source"
    # The tree must be the neutral "update" commit plus exactly this patch.
    test "$(git log -1 --format=%s)" = "update"
    if ! git apply --check --reverse "$patch" 2>/dev/null; then
        git checkout -- zookeeper-server/src/main
        rm -f zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/SpeculaTrace.java
        git apply "$patch"
    fi
    git diff --stat | tee "$log_root/harness-applied-patch.stat"
}

build() {
    ( cd "$work_source" && JAVA_HOME="$java_home" timeout 1200s \
        mvn "${mvn_flags[@]}" -pl zookeeper-server -am -DskipTests install ) \
        > "$log_root/build-instrumented-new.log" 2>&1
}

run_case() {
    local scenario="$1" selector="$2" budget="${3:-300s}"
    local trace="$trace_root/$scenario.ndjson"
    local log="$log_root/harness-$scenario.log"
    if [[ -e "$trace" ]]; then
        mv "$trace" "$trace.previous.$BASHPID"
    fi
    set +e
    ( cd "$work_source" && JAVA_HOME="$java_home" timeout "$budget" \
        mvn "${mvn_flags[@]}" -pl zookeeper-server \
        -Dspecula.trace.file="$trace" \
        -Dspecula.trace.scenario="$scenario" \
        -DfailIfNoTests=false -Dsurefire.failIfNoSpecifiedTests=false \
        -Dtest="$selector" test ) > "$log" 2>&1
    local rc=$?
    set -e
    echo "$scenario rc=$rc trace_lines=$(wc -l < "$trace" 2>/dev/null || echo 0)" | tee -a "$log_root/harness-summary.txt"
    test -s "$trace"
}

apply_instrumentation
build
: > "$log_root/harness-summary.txt"
selected="${SPECULA_SCENARIOS:-follower-snap follower-diff quorum-startup-mutation-shutdown leader-abandon-restart-recovery diff-sync-consistency}"
for sc in $selected; do
    case "$sc" in
        follower-snap) run_case follower-snap 'Zab1_0Test#testNormalFollowerRun' ;;
        follower-diff) run_case follower-diff 'Zab1_0Test#testNormalFollowerRunWithDiff' ;;
        quorum-startup-mutation-shutdown) run_case quorum-startup-mutation-shutdown 'QuorumPeerMainTest#testQuorum' ;;
        leader-abandon-restart-recovery) run_case leader-abandon-restart-recovery 'QuorumPeerMainTest#testEarlyLeaderAbandonment' ;;
        diff-sync-consistency) run_case diff-sync-consistency 'DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog' 400s ;;
        repro-initial-state-failure)
            # Reproduction scenario for model finding MC-2 (harness-only test file).
            cp "$output_root/harness/repro/SpeculaInitialStateFailureReproTest.java" \
               "$work_source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/"
            run_case repro-initial-state-failure 'SpeculaInitialStateFailureReproTest' 500s || true ;;
        *) echo "unknown scenario $sc" >&2; exit 2 ;;
    esac
done
