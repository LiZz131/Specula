#!/usr/bin/env bash
set -euo pipefail

work_source=/work/work-source
output_root=/work/prior/.specula-output
trace_root="$output_root/traces"
log_root="$output_root/spec/output"
java_home=/usr/lib/jvm/java-21-openjdk-amd64

mkdir -p "$trace_root" "$log_root"

run_case() {
    local scenario="$1"
    local selector="$2"
    local trace="$trace_root/$scenario.ndjson"
    local log="$log_root/harness-$scenario.log"
    if [[ -e "$trace" ]]; then
        mv "$trace" "$trace.previous.$BASHPID"
    fi
    (
        cd "$work_source"
        JAVA_HOME="$java_home" timeout 240s mvn -pl zookeeper-server \
            -Dmaven.javadoc.skip=true \
            -Dcheckstyle.skip -Dspotbugs.skip \
            -Dspecula.trace.file="$trace" \
            -Dspecula.trace.scenario="$scenario" \
            -Dtest="$selector" test
    ) 2>&1 | tee "$log"
    test -s "$trace"
}

run_case follower-snap 'Zab1_0Test#testNormalFollowerRun'
run_case follower-diff 'Zab1_0Test#testNormalFollowerRunWithDiff'
run_case quorum-startup-mutation-shutdown 'QuorumPeerMainTest#testQuorum'
run_case leader-abandon-restart-recovery 'QuorumPeerMainTest#testEarlyLeaderAbandonment'
