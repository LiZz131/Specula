#!/usr/bin/env bash
# Usage: run-repro.sh <new|old> <TestClass> <run-id>
# Runs a reproduction test on the instrumented new artifact or the old-control worktree.
set -uo pipefail
OUTPUT=/work/current/.specula-output
VARIANT=$1; TEST=$2; RID=$3
if [ "$VARIANT" = new ]; then TREE="$OUTPUT/artifact"; else TREE="$OUTPUT/work-old"; fi
TEST_DIR="$TREE/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum"
cp "$OUTPUT/harness/repro/$TEST.java" "$TEST_DIR/"
TRACE="$OUTPUT/traces/repro-$RID-$VARIANT.ndjson"
rm -f "$TRACE"
rc=0
( cd "$TREE" && timeout 15m mvn -B -pl zookeeper-server -am -Dcheckstyle.skip=true -Dspotbugs.skip=true \
    -Dmaven.javadoc.skip=true -Dsurefire.failIfNoSpecifiedTests=false -DfailIfNoTests=false \
    -Dtest="$TEST" -Dspecula.trace.file="$TRACE" test ) > "$OUTPUT/spec/output/repro/$RID-$VARIANT.log" 2>&1 || rc=$?
rm -f "$TEST_DIR/$TEST.java"
echo "$RID $VARIANT rc=$rc trace_lines=$(wc -l < "$TRACE" 2>/dev/null || echo 0)"
grep -h "SPECULA-REPRO" "$TREE"/zookeeper-server/target/surefire-reports/*$TEST*-output.txt 2>/dev/null | sed 's/.*SPECULA-REPRO/SPECULA-REPRO/' | head -20
grep -E "Tests run:|AssertionFailed|expected:" "$OUTPUT/spec/output/repro/$RID-$VARIANT.log" | head -5
