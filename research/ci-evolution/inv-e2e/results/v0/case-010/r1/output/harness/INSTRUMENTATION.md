# Harness instrumentation guide (schema v3, updated source)

- Rebuild/rerun: `bash /work/current/.specula-output/harness/run.sh` (set `SPECULA_TRACE_RUN_ID` to a new label; traces are never overwritten).
- The script resets `artifact/` to `update` (b16ba71), applies `harness/patches/instrumentation.patch`, builds, and runs three JUnit scenarios under `timeout 15m` each.
- Changed points relative to V0 (all in `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/`):
  - `SpeculaTrace.java`: schema v3 envelope, `memState` / `durableState` real-object readers, floor zxid map, update-local probe methods.
  - `Learner.java`: probes in `registerWithLeader` (after ACKEPOCH), SNAP/TRUNC branches, PROPOSAL/COMMIT cases, NEWLEADER snapshot (suppression flag around `takeSnapshot`), before NEWLEADER ACK, after `startServing`, and in `shutdown` after `zk.shutdown(full)`.
- To add a field: extend `memState`/`durableState` or pass a value into the event-specific method; then add a required check in `Trace.tla`.
- To regenerate the patch after editing the artifact: `git -C artifact add -N <new files>; git -C artifact diff > harness/patches/instrumentation.patch`.
