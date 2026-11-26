#!/usr/bin/env bash
# Reproduction runner: runs one JUnit selector on the updated (new-clean, no
# instrumentation) and the old (baseline, old-src) trees with the same test
# sources (harness/src).  Usage: repro.sh <label> <selector> [new|old|both|custom]
# 'custom' runs on the ZooKeeper source tree given by SPECULAR_REPRO_TREE (any
# revision with the same test infrastructure; the tree must already have its
# zookeeper-jute module installed in /work/.cache/m2 or be built with -am).
set -uo pipefail
out=/work/current/.specular-output
label=$1; selector=$2; which=${3:-both}
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
for v in new old custom; do
  [[ "$which" == both && $v != custom || "$which" == "$v" ]] || continue
  if [[ $v == new ]]; then tree=$out/harness/work/new-clean
  elif [[ $v == old ]]; then tree=$out/harness/work/old-src
  else tree=${SPECULAR_REPRO_TREE:?set SPECULAR_REPRO_TREE}; fi
  cp $out/harness/src/SpecularReproTest.java $out/harness/src/SpecularUpdateScenariosTest.java \
     $tree/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/
  log=$out/spec/output/repro-$label-$v.log
  { echo "# tree: $tree  commit: $(git -C $tree rev-parse --short HEAD)"; echo "# selector: $selector"; echo "# started: $(date -u +%FT%TZ)"; } > $log
  ( cd $tree && timeout 900s mvn -B -pl zookeeper-server test -Dcheckstyle.skip -Dspotbugs.skip \
      -Dmaven.javadoc.skip=true -Dmaven.repo.local=/work/.cache/m2 -DfailIfNoTests=false \
      -Dsurefire.failIfNoSpecifiedTests=false -Dtest="$selector" ) >> $log 2>&1
  rc=$?
  cls=${selector%%#*}
  rep=$tree/zookeeper-server/target/surefire-reports/org.apache.zookeeper.server.quorum.$cls-output.txt
  [[ -f $rep ]] && cp $rep $out/spec/output/repro-$label-$v-surefire-output.txt
  res=$(grep -E "Tests run:.*Fail" $log | tail -1)
  echo "$label $v rc=$rc $res" | tee -a $out/spec/output/repro-summary.log
done
