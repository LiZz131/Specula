#!/usr/bin/env bash
# Specular incremental harness (rebased from the V0 prior harness).
# One command: (re)apply instrumentation to a fresh copy of the updated source,
# build it, run the selected scenarios, and write fresh NDJSON traces.
#   usage: harness/run.sh [scenario ...]      (default: all scenarios)
set -euo pipefail
out_root=/work/current/.specular-output
artifact="$out_root/artifact"
work_source="$out_root/work-source"
trace_root="$out_root/traces/fresh"
log_root="$out_root/spec/output/incr/harness"
patch="$out_root/harness/patches/instrumentation.patch"
java_home=/usr/lib/jvm/java-21-openjdk-amd64
m2=/work/.cache/m2
mkdir -p "$trace_root" "$log_root"

prepare() {
    if [[ ! -d "$work_source/.git" ]]; then
        cp -a "$artifact" "$work_source"
    fi
    ( cd "$work_source"
      git checkout -q -- . && git clean -q -fd -e target/
      git apply --whitespace=nowarn "$patch" )
    ( cd "$work_source"
      JAVA_HOME="$java_home" timeout 1500s mvn -B -pl zookeeper-server -am install -DskipTests \
          -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip \
          -Dmaven.repo.local="$m2" ) > "$log_root/build-instrumented.log" 2>&1
}

run_case() {
    local scenario="$1" selector="$2" tmo="${3:-300}"
    local trace="$trace_root/$scenario.ndjson" log="$log_root/harness-$scenario.log"
    [[ -e "$trace" ]] && mv "$trace" "$trace.superseded.$(date +%s)"
    local rc=0
    ( cd "$work_source"
      JAVA_HOME="$java_home" timeout "${tmo}s" mvn -B -pl zookeeper-server \
          -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip \
          -Dmaven.repo.local="$m2" -DfailIfNoTests=false \
          -Dspecular.trace.file="$trace" -Dspecular.trace.scenario="$scenario" \
          -Dtest="$selector" test ) > "$log" 2>&1 || rc=$?
    echo "{\"scenario\":\"$scenario\",\"selector\":\"$selector\",\"exit_code\":$rc,\"trace\":\"traces/fresh/$scenario.ndjson\",\"records\":$( [[ -s $trace ]] && wc -l < "$trace" || echo 0)}" >> "$log_root/harness-results.ndjson"
    test -s "$trace"
}

declare -A SEL=(
  [follower-snap]='Zab1_0Test#testNormalFollowerRun'
  [follower-diff]='Zab1_0Test#testNormalFollowerRunWithDiff'
  [quorum-startup-mutation-shutdown]='QuorumPeerMainTest#testQuorum'
  [leader-abandon-restart-recovery]='QuorumPeerMainTest#testEarlyLeaderAbandonment'
  [diff-sync-consistency]='DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog'
)
ORDER=(follower-diff follower-snap quorum-startup-mutation-shutdown leader-abandon-restart-recovery diff-sync-consistency)
[[ $# -gt 0 ]] && ORDER=("$@")
if [[ "${SKIP_PREPARE:-0}" != 1 ]]; then prepare; fi
status=0
for sc in "${ORDER[@]}"; do run_case "$sc" "${SEL[$sc]}" 300 || status=1; done
exit $status
