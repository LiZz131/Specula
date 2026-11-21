# Exact commands (case-010)

Build/test/trace collection (all under `timeout 15m` per Maven invocation):
- `harness/run-all.sh` = `harness/run.sh` (new code; scenarios election-ordered, restart-catchup, diff-sync-after-snap, snap-complete) + `harness/run-old-control.sh` + `harness/repro/run-repro.sh new|old SpeculaTruncAbortReproTest trunc-abort`.
- Maven invocation (from the artifact or `work-old` root): `mvn -B -pl zookeeper-server -am -Dcheckstyle.skip=true -Dspotbugs.skip=true -Dmaven.javadoc.skip=true -Dsurefire.failIfNoSpecifiedTests=false -DfailIfNoTests=false -Dtest=<Class#method> -Dspecula.trace.file=<trace> test` (MAVEN_OPTS=-Dmaven.repo.local=/work/.cache/m2).

Trace validation (`spec/run_trace.sh <trace> <name> [cfg] [module]`):
- `JSON=<trace> timeout 10m java -XX:+UseParallelGC -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -workers 1 -metadir /dev/shm/specula-e2e-case-010/trace-<name>-<pid> -config <cfg> <module>.tla` (metadir removed afterwards; log `spec/output/trace-<name>.log`).

Model checking (`spec/run_tlc.sh <module> <cfg> <name> <minutes> <workers> [sim-depth]`, batches via `spec/campaign.sh <list> <parallelism>` with lists `spec/r2-batchA.txt`, `spec/r2-batchB.txt`, `spec/r2-sim.txt`):
- `timeout $((MIN*60+300)) java -Xmx<heap> -XX:+UseParallelGC -Dtlc2.TLC.stopAfter=$((MIN*60)) -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tlc2.TLC -workers <W> -metadir /dev/shm/specula-e2e-case-010/mc-<name>-<pid> -config <cfg> [-simulate -depth <D>] -dumpTrace tla output/mc/<name>.cex.tla <module>.tla` (metadir removed afterwards).

Static preflight: `java -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tla2sany.SANY <module>.tla` (`spec/output/generation-sany.log`); cfg operator resolution `spec/output/generation-cfg-preflight.log`.
