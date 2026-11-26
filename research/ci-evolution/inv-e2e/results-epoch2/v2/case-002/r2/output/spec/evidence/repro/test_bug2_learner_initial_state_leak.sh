#!/usr/bin/env bash
# Reproduction for CR-2 (learner failure between NEWLEADER and UPTODATE leaves
# an INITIAL ZooKeeperServer whose shutdown is skipped).
# Usage: test_bug2_learner_initial_state_leak.sh [new|old] [runs]
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
cp "$out/repro/LearnerInitialStateLeakReproTest.java" "$src/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/"
for r in $(seq 1 "$runs"); do
  log=$log_root/bug2-$which-run$r.log
  (cd "$src" && JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 timeout 900s mvn -B -pl zookeeper-server -am \
     -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -DfailIfNoTests=false \
     -Dsurefire.failIfNoSpecifiedTests=false -Dtest=LearnerInitialStateLeakReproTest test) > "$log" 2>&1
  rc=$?
  obs=$(grep -ho "REPRO-OBSERVATION.*" "$src"/zookeeper-server/target/surefire-reports/*LearnerInitialStateLeakReproTest-output.txt 2>/dev/null | tr '\n' ' ')
  res=$(grep -oE "Tests run:[^<]*LearnerInitialStateLeakReproTest|(leaked [A-Za-z]+ instances[^=]*|data tree \(election vote\) lags[^=]*)==> [^\"]*" "$log" | head -2 | tr '\n' ' ')
  echo "which=$which commit=$(git -C "$src" rev-parse --short HEAD) run=$r mvn_exit=$rc $obs $res log=${log#$out/}" | tee -a "$log_root/bug2-summary.log"
  for f in "$src"/zookeeper-server/target/surefire-reports/*LearnerInitialStateLeakReproTest*; do
    b=$(basename "$f"); cp "$f" "$log_root/${b%.*}-$which-run$r.${b##*.}"; done
done
