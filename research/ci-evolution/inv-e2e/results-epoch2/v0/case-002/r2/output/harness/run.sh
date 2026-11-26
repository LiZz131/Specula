#!/usr/bin/env bash
# Specular harness (rebased from the prior Specula V0 harness onto the updated
# source).  One command: copy the updated tree, apply the instrumentation patch,
# build with JDK 11, run the selected scenarios, keep fresh NDJSON traces.
#   harness/run.sh [--no-prepare] [scenario ...]
# Exit status: nonzero if a selected scenario produced an empty trace.  A test
# assertion failure is recorded (spec/output/harness-<scenario>.log) but does not
# discard the trace: update scenarios assert protocol expectations that the
# updated implementation may violate.
set -uo pipefail
out=/work/current/.specular-output
src="${SPECULAR_SOURCE:-$out/artifact}"
work="${SPECULAR_WORK:-$out/harness/work/new-src}"
patch="$out/harness/patches/instrumentation.patch"
trace_root="${SPECULAR_TRACE_ROOT:-$out/traces}"
log_root="$out/spec/output"
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
m2=/work/.cache/m2
mkdir -p "$trace_root" "$log_root"

prepare=1
if [[ "${1:-}" == "--no-prepare" ]]; then prepare=0; shift; fi
if (( prepare )); then
    rm -rf "$work"
    cp -a "$src" "$work"
    git -C "$work" checkout -q -- . && git -C "$work" apply "$patch" || { echo "patch failed"; exit 2; }
    ( cd "$work" && timeout 1200s mvn -B -pl zookeeper-server -am install -DskipTests \
        -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Dmaven.repo.local="$m2" ) \
        > "$log_root/build-instrumented.log" 2>&1 || { echo "build failed"; exit 3; }
fi

declare -A SEL=(
  [follower-snap]='Zab1_0Test#testNormalFollowerRun'
  [follower-diff]='Zab1_0Test#testNormalFollowerRunWithDiff'
  [quorum-startup-mutation-shutdown]='QuorumPeerMainTest#testQuorum'
  [leader-abandon-restart-recovery]='QuorumPeerMainTest#testEarlyLeaderAbandonment'
  [diff-sync-uncommitted]='DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog'
  [diff-commit-after-newleader]='SpecularUpdateScenariosTest#testCommitAfterNewLeaderForPreNewLeaderProposal'
  [diff-ack-before-newleader-ack]='SpecularUpdateScenariosTest#testProposalAckBeforeNewLeaderAck'
)
ORDER=(follower-snap follower-diff quorum-startup-mutation-shutdown leader-abandon-restart-recovery
       diff-sync-uncommitted diff-commit-after-newleader diff-ack-before-newleader-ack)
if (( $# > 0 )); then ORDER=("$@"); fi

status=0
for scenario in "${ORDER[@]}"; do
    selector="${SEL[$scenario]}"
    trace="$trace_root/$scenario.ndjson"
    log="$log_root/harness-$scenario.log"
    rm -f "$trace"
    ( cd "$work" && timeout 600s mvn -B -pl zookeeper-server test -Dcheckstyle.skip -Dspotbugs.skip -Dmaven.javadoc.skip=true \
        -Dmaven.repo.local="$m2" -DfailIfNoTests=false -Dsurefire.failIfNoSpecifiedTests=false \
        -Dspecular.trace.file="$trace" -Dspecular.trace.scenario="$scenario" \
        -Dtest="$selector" ) > "$log" 2>&1
    rc=$?
    n=$( [[ -s "$trace" ]] && wc -l < "$trace" || echo 0 )
    echo "$scenario selector=$selector mvn_rc=$rc events=$n" | tee -a "$log_root/harness-summary.log"
    [[ -s "$trace" ]] || status=1
done
exit $status
