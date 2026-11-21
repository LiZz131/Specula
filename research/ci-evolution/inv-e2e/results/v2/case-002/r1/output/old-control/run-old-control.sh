#!/usr/bin/env bash
# Attribution control: run the SAME observation test on the exact-old (baseline)
# source, extracted read-only with `git archive baseline`.  No instrumentation.
set -uo pipefail
root=/work/current/.specula-output/old-control
export MAVEN_OPTS="${MAVEN_OPTS:--Dmaven.repo.local=/work/.cache/m2}"
cd "$root/tree"
for t in newLeaderAckPrecedesDurability commitOfStreamedProposalAfterNewLeader; do
  obs="$root/old-$t"
  rm -f "$obs.observation.json"
  JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 timeout 600s mvn -B -pl zookeeper-server \
     -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -DfailIfNoTests=false \
     -Dspecula.trace.file="$obs" -Dtest="SpeculaUpdateObservationTest#$t" test > "$root/old-$t.log" 2>&1
  echo "$t exit=$?"
  cp zookeeper-server/target/surefire-reports/*SpeculaUpdateObservationTest*-output.txt "$root/old-$t-surefire-output.txt" 2>/dev/null
done
