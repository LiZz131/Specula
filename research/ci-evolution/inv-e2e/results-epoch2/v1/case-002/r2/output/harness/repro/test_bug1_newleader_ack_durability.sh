#!/usr/bin/env bash
# Reproduction driver for MC-1.  Copies the repro test into an UNINSTRUMENTED
# copy of a source tree and runs it with a bounded timeout.
#   usage: harness/repro/test_bug1_newleader_ack_durability.sh <label> <source-tree>
# e.g.  ... new /work/current/.specular-output/artifact
#       ... old /work/current/.specular-output/controls/old-pristine
set -uo pipefail
label="$1"; src="$2"
here="$(cd "$(dirname "$0")" && pwd)"
out=/work/current/.specular-output/spec/output/incr/repro; mkdir -p "$out"
tree=/work/current/.specular-output/controls/repro-$label
rm -rf "$tree"; cp -a "$src" "$tree"
( cd "$tree" && git status --short | head -5 ) > "$out/repro-$label-tree-status.txt" 2>&1
cp "$here/NewLeaderAckDurabilityReproTest.java" "$tree/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/"
( cd "$tree" && REPRO_SLOW_APPEND_MS="${SLOW_APPEND_MS:-3000}" JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 timeout 600s mvn -B -pl zookeeper-server \
    -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Dmaven.repo.local=/work/.cache/m2 \
    -Dtest=NewLeaderAckDurabilityReproTest test ) > "$out/repro-$label.log" 2>&1
rc=$?
echo "exit=$rc" >> "$out/repro-$label.log"
grep -h "REPRO:" "$tree"/zookeeper-server/target/surefire-reports/*NewLeaderAckDurabilityReproTest*-output.txt > "$out/repro-$label-markers.txt" 2>/dev/null
grep -E "Tests run:|FAIL|Data inconsistency" "$out/repro-$label.log" | head -5
exit $rc
