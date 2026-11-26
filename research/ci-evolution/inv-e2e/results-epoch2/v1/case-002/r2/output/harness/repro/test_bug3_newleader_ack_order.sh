#!/usr/bin/env bash
# Reproduction driver for CR-3.  Copies the repro test into an UNINSTRUMENTED
# copy of a source tree and runs it with a bounded timeout.
#   usage: harness/repro/test_bug1_newleader_ack_durability.sh <label> <source-tree>
# e.g.  ... new /work/current/.specular-output/artifact
#       ... old /work/current/.specular-output/controls/old-pristine
set -uo pipefail
label="$1"; src="$2"
here="$(cd "$(dirname "$0")" && pwd)"
out=/work/current/.specular-output/spec/output/incr/repro; mkdir -p "$out"
tree=/work/current/.specular-output/controls/repro3-$label
rm -rf "$tree"; cp -a "$src" "$tree"
( cd "$tree" && git status --short | head -5 ) > "$out/repro3-$label-tree-status.txt" 2>&1
cp "$here/NewLeaderAckOrderReproTest.java" "$tree/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/"
( cd "$tree" && REPRO_ACK_DELAY_MS="${ACK_DELAY_MS:-500}" JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 timeout 600s mvn -B -pl zookeeper-server \
    -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Dmaven.repo.local=/work/.cache/m2 \
    -Dtest=NewLeaderAckOrderReproTest test ) > "$out/repro3-$label.log" 2>&1
rc=$?
echo "exit=$rc" >> "$out/repro3-$label.log"
grep -h "REPRO-CR3:" "$tree"/zookeeper-server/target/surefire-reports/*NewLeaderAckOrderReproTest*-output.txt > "$out/repro3-$label-markers.txt" 2>/dev/null
grep -E "Tests run:|FAIL|Data inconsistency" "$out/repro3-$label.log" | head -5
exit $rc
