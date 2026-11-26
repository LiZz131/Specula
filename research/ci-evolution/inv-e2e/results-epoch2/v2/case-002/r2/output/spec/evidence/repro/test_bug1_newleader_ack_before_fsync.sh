#!/usr/bin/env bash
# Reproduction for MC-1 (NEWLEADER ACK before the DIFF-synced txn is durable).
# Runs repro/NewLeaderAckDurabilityReproTest.java against
#   new: artifact HEAD  (update 2efbdfc, uninstrumented)
#   old: artifact commit baseline 1414ebf (control)
# Usage: test_bug1_newleader_ack_before_fsync.sh [new|old] [runs] [label] [extra -D options]
#   e.g. ... new 1 control-noimage "-Drepro.restoreImages=false"
set -uo pipefail
out=/work/current/.specular-output
which=${1:-new}; runs=${2:-1}; label=${3:-default}; extra=${4:-}
src=$out/repro/work-$which
log_root=$out/repro/logs; mkdir -p "$log_root"
export MAVEN_OPTS="${MAVEN_OPTS:--Dmaven.repo.local=/work/.cache/m2}"
if [[ ! -d $src/.git ]]; then
  rm -rf "$src"; mkdir -p "$src"; rsync -a "$out/artifact/" "$src/"
  if [[ $which == old ]]; then git -C "$src" checkout -q 1414ebf; fi
fi
echo "source=$src commit=$(git -C "$src" rev-parse --short HEAD) dirty_files=$(git -C "$src" status --short | wc -l)"
cp "$out/repro/NewLeaderAckDurabilityReproTest.java" "$src/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/"
for r in $(seq 1 "$runs"); do
  log=$log_root/bug1-$which-$label-run$r.log
  (cd "$src" && JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 timeout 900s mvn -B -pl zookeeper-server -am \
     -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -DfailIfNoTests=false \
     -Dsurefire.failIfNoSpecifiedTests=false $extra -Dtest=NewLeaderAckDurabilityReproTest test) > "$log" 2>&1
  rc=$?
  obs=$(grep -ho "REPRO-OBSERVATION.*" "$src"/zookeeper-server/target/surefire-reports/*NewLeaderAckDurabilityReproTest-output.txt 2>/dev/null | tr '\n' ' ')
  res=$(grep -E "Tests run:.*NewLeaderAckDurabilityReproTest|Data inconsistency detected[^\"]*" -o "$log" | head -2 | tr '\n' ' ')
  echo "which=$which label=$label extra=$extra run=$r mvn_exit=$rc $obs $res log=${log#$out/}" | tee -a "$log_root/bug1-summary.log"
  for f in "$src"/zookeeper-server/target/surefire-reports/*NewLeaderAckDurabilityReproTest*; do
    b=$(basename "$f"); cp "$f" "$log_root/${b%.*}-$which-$label-run$r.${b##*.}"; done
done
