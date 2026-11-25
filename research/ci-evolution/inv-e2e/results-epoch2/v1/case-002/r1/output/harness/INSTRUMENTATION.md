# Harness instrumentation (V1, rebased)

Probes are synchronous and opt-in (`-Dspecula.trace.file`). The patch
`patches/instrumentation.patch` is the V0 patch rebased onto commit `update`
of `../artifact` plus V1 update probes:

- `BroadcastReady` moved after `zk.startServing()` (source drift; V0 hunk
  targeted the removed `zk.startup()` call).
- `NewLeaderAckSent` (Learner NEWLEADER branch, after the ACK write) with the
  logged-at-NEWLEADER zxid/count, TxnDurable watermark, raw fsync watermark and
  server running state.
- `NewLeaderAckReceived` (Leader.waitForNewLeaderAck decision and disposition).
- `TxnAckSent` (SendAckRequestProcessor after writing a txn ACK).
- `ShutdownSkipped` (ZooKeeperServer / LearnerZooKeeperServer shutdown early
  return, with server state).
- `SyncRequestProcessor.flush`: fsync watermark recorded immediately after
  `ZKDatabase.commit()`; `TxnDurable` emission updates the emitted-durable
  watermark under the trace lock.

Harness-only test: `SpeculaNewLeaderAckOrderTest` (copied into
`work-source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/`
by the patch) plays the leader side of `Zab1_0Test` with a 7-txn DIFF and records
which ACK the learner writes first.

Rebuild/rerun: `timeout 3600s harness/run.sh` (prepares a fresh copy of
`artifact/`, applies the patch, builds with JDK 11, runs all scenarios);
`SKIP_PREPARE=1` reuses the prepared copy; `SCENARIOS=...` selects scenarios.
