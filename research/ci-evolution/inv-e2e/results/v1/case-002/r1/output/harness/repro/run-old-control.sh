#!/usr/bin/env bash
# Old-version control for the MC-2 reproduction: baseline commit + the update's
# DIFFSyncConsistencyTest fixture + the repro test (no instrumentation, no install).
set -uo pipefail
root=/work/current/.specula-output
cd "$root/old-control"
test "$(git rev-parse HEAD)" = "1414ebfb1d16fd81abc38550a96950d919ecf805"
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 timeout 1500s mvn -B -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip=true \
  -pl zookeeper-server -DfailIfNoTests=false -Dsurefire.failIfNoSpecifiedTests=false \
  -Dtest="${1:-SpeculaInitialStateFailureReproTest}" test > "$root/spec/output/old-control-${2:-repro}.log" 2>&1
rc=$?
echo "old-control rc=$rc" >> "$root/spec/output/old-control-${2:-repro}.log"
grep -h "SPECULA-REPRO" zookeeper-server/target/surefire-reports/*-output.txt 2>/dev/null >> "$root/spec/output/old-control-${2:-repro}.log"
exit 0
