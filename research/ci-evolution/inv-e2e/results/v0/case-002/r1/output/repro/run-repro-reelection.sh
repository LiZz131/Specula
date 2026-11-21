#!/usr/bin/env bash
# U-LOSS consequence: in-process re-election after learners fail between NEWLEADER and UPTODATE.
set -uo pipefail
out=/work/current/.specula-output/repro
java_home=/usr/lib/jvm/java-21-openjdk-amd64
repo=/work/.cache/m2
ledger="$out/repro-results.ndjson"
true
for t in new old; do
  cp /work/current/.specula-output/harness/tests/SpeculaReelectionAfterSyncFailureTest.java \
     "$out/$t-tree/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/"
done
for i in 1 2; do
  for t in new old; do
    log="$out/$t-reelection-run$i.log"
    (cd "$out/$t-tree" && JAVA_HOME=$java_home timeout 600s mvn -B -Dmaven.repo.local=$repo -pl zookeeper-server \
      -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip \
      -Dtest='SpeculaReelectionAfterSyncFailureTest#testCommittedTxnVisibleAfterInProcessReelection' test) > "$log" 2>&1
    rc=$?
    summary=$(grep -m1 -E "Tests run: [0-9]+, Failures" "$log" | sed 's/"//g')
    echo "{\"tree\":\"$t\",\"test\":\"SpeculaReelectionAfterSyncFailureTest#testCommittedTxnVisibleAfterInProcessReelection\",\"run\":$i,\"exit\":$rc,\"summary\":\"$summary\",\"log\":\"repro/$(basename $log)\"}" >> "$ledger"
  done
done
