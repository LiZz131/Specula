#!/usr/bin/env bash
# Supplementary reproductions of model counterexamples.
#   new : instrumented update revision (harness/build/work-source), traced
#   old : uninstrumented baseline commit 1414ebf (control)
# Usage: timeout 3000s bash harness/repro/run-repro.sh <new|old> <run-id> [TestClass]
#   TestClass: StaleTreeReelectionReproTest (MC-2, default), AckBeforeFsyncReproTest (MC-1),
#              TruncAbsentZxidReproTest (MC-3)
set -uo pipefail
out="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
which="${1:-new}"; rid="${2:-1}"; cls="${3:-StaleTreeReelectionReproTest}"
rel=zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum
java_home=/usr/lib/jvm/java-21-openjdk-amd64
mvn_common=(-B -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip=true)
tag=$(echo "$cls" | sed 's/ReproTest//' | tr 'A-Z' 'a-z')
log="$out/spec/output/repro-$tag-$which-$rid.log"
if [[ "$which" == new ]]; then
    tree="$out/harness/build/work-source"
    trace="$out/traces/repro-$tag-$rid.ndjson"
    rm -f "$trace"
    cp "$out/harness/repro/$cls.java" "$tree/$rel/"
    (cd "$tree" && JAVA_HOME="$java_home" timeout 900s mvn "${mvn_common[@]}" -pl zookeeper-server \
        -Dspecula.trace.file="$trace" -Dspecula.trace.scenario="repro-$tag" \
        -Dsurefire.failIfNoSpecifiedTests=false -Dtest="$cls" test) > "$log" 2>&1
else
    tree="$out/harness/build/old-source-control"
    if [[ ! -d "$tree" ]]; then
        mkdir -p "$tree"; git -C "$out/artifact" archive 1414ebf | tar -x -C "$tree"
    fi
    cp "$out/harness/repro/$cls.java" "$tree/$rel/"
    (cd "$tree" && JAVA_HOME="$java_home" timeout 1500s mvn "${mvn_common[@]}" -pl zookeeper-server -am \
        -Dsurefire.failIfNoSpecifiedTests=false -DfailIfNoTests=false -Dtest="$cls" test) > "$log" 2>&1
fi
rc=$?
echo "# exit: $rc" >> "$log"
echo "# source: $(if [[ $which == new ]]; then git -C "$out/artifact" rev-parse HEAD; else echo 1414ebf; fi)" >> "$log"
grep -h "REPRO" "$tree"/zookeeper-server/target/surefire-reports/*"$cls"*-output.txt 2>/dev/null | sed 's/^.*REPRO/REPRO/' >> "$log"
grep -E "Tests run:.*$cls|REPRO|BUILD" "$log" | tail -6
