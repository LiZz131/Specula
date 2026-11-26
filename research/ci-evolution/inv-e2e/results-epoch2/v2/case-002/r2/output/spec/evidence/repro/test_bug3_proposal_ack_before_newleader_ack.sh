#!/usr/bin/env bash
# Reproduction for CR-3 (a proposal ACK can be consumed as the NEWLEADER ACK)

# Usage: test_bug3_proposal_ack_before_newleader_ack.sh [new|old] [runs]
set -uo pipefail
out=/work/current/.specular-output
which=${1:-new}; runs=${2:-1}
src=$out/repro/work-$which
log_root=$out/repro/logs; mkdir -p "$log_root"
export MAVEN_OPTS="${MAVEN_OPTS:--Dmaven.repo.local=/work/.cache/m2}"
if [[ ! -d $src/.git ]]; then
  rm -rf "$src"; mkdir -p "$src"; rsync -a "$out/artifact/" "$src/"
  if [[ $which == old ]]; then git -C "$src" checkout -q 1414ebf; fi
fi
cp "$out/repro/NewLeaderAckOrderReproTest.java" "$src/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/"
for r in $(seq 1 "$runs"); do
  log=$log_root/bug3-$which-run$r.log
  (cd "$src" && JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 timeout 900s mvn -B -pl zookeeper-server -am \
     -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -DfailIfNoTests=false \
     -Dsurefire.failIfNoSpecifiedTests=false -Dtest=NewLeaderAckOrderReproTest test) > "$log" 2>&1
  rc=$?
  obs=$(grep -ho "REPRO-OBSERVATION.*" "$src"/zookeeper-server/target/surefire-reports/*NewLeaderAckOrderReproTest-output.txt 2>/dev/null | tr '\n' ' ')
  res=$(grep -oE "Tests run:[^<]*NewLeaderAckOrderReproTest|NEWLEADER quorum was missed[^=]*==> [^\"]*" "$log" | head -2 | tr '\n' ' ')
  rej=$(grep -c "is from a different epoch" "$src"/zookeeper-server/target/surefire-reports/*NewLeaderAckOrderReproTest-output.txt 2>/dev/null)
  echo "which=$which rejected_newleader_acks=$rej commit=$(git -C "$src" rev-parse --short HEAD) run=$r mvn_exit=$rc $obs $res log=${log#$out/}" | tee -a "$log_root/bug3-summary.log"
  for f in "$src"/zookeeper-server/target/surefire-reports/*NewLeaderAckOrderReproTest*; do
    b=$(basename "$f"); cp "$f" "$log_root/${b%.*}-$which-run$r.${b##*.}"; done
done
