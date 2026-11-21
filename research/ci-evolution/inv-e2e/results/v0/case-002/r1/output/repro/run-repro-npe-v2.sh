#!/usr/bin/env bash
# MC-1 reproduction with the race-free assertion (waits for BROADCAST); 3 runs per tree.
set -uo pipefail
out=/work/current/.specula-output/repro
java_home=/usr/lib/jvm/java-21-openjdk-amd64
repo=/work/.cache/m2
ledger="$out/repro-results.ndjson"
until grep -q '^EXIT=' "$out/run-capture.log" 2>/dev/null; do sleep 5; done
mkdir -p "$out/surefire"
sel='SpeculaSyncUpdateTest#testCommitOfForwardedProposalAfterNewLeader'
for i in 1 2 3; do for t in new old; do
  log="$out/$t-npe-v2-run$i.log"
  (cd "$out/$t-tree" && JAVA_HOME=$java_home timeout 600s mvn -B -Dmaven.repo.local=$repo -pl zookeeper-server \
    -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dtest="$sel" test) > "$log" 2>&1
  rc=$?
  cp "$out/$t-tree/zookeeper-server/target/surefire-reports/org.apache.zookeeper.server.quorum.SpeculaSyncUpdateTest-output.txt" "$out/surefire/$t-npe-v2-run$i-output.txt" 2>/dev/null
  summary=$(grep -m1 -E "Tests run: [0-9]+, Failures" "$log" | sed 's/"//g')
  echo "{\"tree\":\"$t\",\"test\":\"$sel (v2 assertion)\",\"run\":$i,\"exit\":$rc,\"summary\":\"$summary\",\"log\":\"repro/$(basename $log)\",\"server_log\":\"repro/surefire/$t-npe-v2-run$i-output.txt\"}" >> "$ledger"
done; done
