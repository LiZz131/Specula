#!/usr/bin/env bash
# Reproduce update findings on the uninstrumented NEW tree and on an OLD control
# tree (artifact with the two exact-old changed main files from /work/old-source).
set -uo pipefail
out=/work/current/.specula-output/repro
artifact=/work/current/.specula-output/artifact
java_home=/usr/lib/jvm/java-21-openjdk-amd64
repo=/work/.cache/m2
test_src=/work/current/.specula-output/harness/tests/SpeculaSyncUpdateTest.java
rel=zookeeper-server/src/main/java/org/apache/zookeeper/server
ledger="$out/repro-results.ndjson"
: > "$ledger"
prepare() {
  local name="$1" dir="$out/$1-tree"
  rm -rf "$dir"; mkdir -p "$dir"
  (cd "$artifact" && tar --exclude=.git -cf - .) | (cd "$dir" && tar xf -)
  cp "$test_src" "$dir/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/"
  if [[ "$name" == old ]]; then
    cp /work/old-source/$rel/ZooKeeperServer.java "$dir/$rel/ZooKeeperServer.java"
    cp /work/old-source/$rel/quorum/Learner.java "$dir/$rel/quorum/Learner.java"
  fi
  (cd "$dir" && sha256sum $rel/ZooKeeperServer.java $rel/quorum/Learner.java) > "$out/$name-tree.sha256"
  (cd "$dir" && JAVA_HOME=$java_home timeout 1200s mvn -B -Dmaven.repo.local=$repo -pl zookeeper-server install \
      -DskipTests -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip) > "$out/build-$name.log" 2>&1
  echo "{\"tree\":\"$name\",\"step\":\"build\",\"exit\":$?}" >> "$ledger"
}
run() {
  local name="$1" sel="$2" tag="$3" i="$4"
  local dir="$out/$name-tree" log="$out/$name-$tag-run$i.log"
  (cd "$dir" && JAVA_HOME=$java_home timeout 600s mvn -B -Dmaven.repo.local=$repo -pl zookeeper-server \
      -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dtest="$sel" test) > "$log" 2>&1
  local rc=$?
  local summary; summary=$(grep -m1 -E "Tests run: [0-9]+, Failures" "$log" | sed 's/"//g')
  echo "{\"tree\":\"$name\",\"test\":\"$sel\",\"run\":$i,\"exit\":$rc,\"summary\":\"$summary\",\"log\":\"repro/$(basename $log)\"}" >> "$ledger"
}
prepare new; prepare old
for i in 1 2 3; do
  for t in new old; do
    run $t 'SpeculaSyncUpdateTest#testCommitOfForwardedProposalAfterNewLeader' npe $i
    run $t 'SpeculaSyncUpdateTest#testNewLeaderAckOnlyAfterDiffTxnDurable' dur $i
  done
done
run new 'DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog' diffsync 1
run old 'DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog' diffsync 1
