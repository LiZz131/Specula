#!/usr/bin/env bash
# Re-run each reproduction once per tree and preserve the surefire test output (server logs).
set -uo pipefail
out=/work/current/.specula-output/repro
java_home=/usr/lib/jvm/java-21-openjdk-amd64
repo=/work/.cache/m2
ledger="$out/repro-results.ndjson"
true
mkdir -p "$out/surefire"
for sel in 'SpeculaSyncUpdateTest#testCommitOfForwardedProposalAfterNewLeader' \
           'SpeculaSyncUpdateTest#testNewLeaderAckOnlyAfterDiffTxnDurable' \
           'SpeculaReelectionAfterSyncFailureTest#testCommittedTxnVisibleAfterInProcessReelection'; do
  cls=${sel%%#*}; m=${sel##*#}
  for t in new old; do
    log="$out/$t-capture-$m.log"
    (cd "$out/$t-tree" && JAVA_HOME=$java_home timeout 600s mvn -B -Dmaven.repo.local=$repo -pl zookeeper-server \
      -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dtest="$sel" test) > "$log" 2>&1
    rc=$?
    cp "$out/$t-tree/zookeeper-server/target/surefire-reports/org.apache.zookeeper.server.quorum.$cls-output.txt" \
       "$out/surefire/$t-$m-output.txt" 2>/dev/null
    summary=$(grep -m1 -E "Tests run: [0-9]+, Failures" "$log" | sed 's/"//g')
    echo "{\"tree\":\"$t\",\"test\":\"$sel\",\"run\":\"capture\",\"exit\":$rc,\"summary\":\"$summary\",\"log\":\"repro/$(basename $log)\",\"server_log\":\"repro/surefire/$t-$m-output.txt\"}" >> "$ledger"
  done
done
