# Instrumentation (rebased for the update revision)

Apply/build/run: `SPECULA_TRACE_RUN_ID=<label> harness/run.sh` (idempotent `git apply` of `harness/patches/instrumentation.patch` onto `artifact/` at commit `b16ba71`, then one Maven surefire run per scenario under `timeout 20m`). The prior patch is kept as `harness/patches/instrumentation-v0-prior.patch`; it applied cleanly to the new source.

Emitter: `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/SpeculaTrace.java` (schemaVersion 3). All emission and probe bookkeeping (dense txn ids, per-processor unflushed queues, leaked-processor set) happen under `SpeculaTrace.LOCK`, so file order is observation order. Dormant unless `-Dspecula.trace.file` is set.

Changed/added probe points (new-source symbols):

| Event | Location | Notes |
|---|---|---|
| LearnerShutdown | `Learner.shutdown`, after `zk.shutdown(isSnap)` | `served` (= `zk.isRunning()` before), `full`, `leakedNow` (sync thread alive and not yet marked), `leakedQueue`, `dbInit` (after) |
| ReloadDatabase / RestartLoadDatabase | `QuorumPeer.loadDataBase` end; ReloadDatabase when called from `getLastLoggedZxid` (thread-local flag) | `state.recovered` = modeled txns <= loaded snapshot zxid, then replayed WAL records from `ZKDatabase.getCommittedLog()` |
| LoadSyncSnapshot | `Learner.syncWithLeader` SNAP branch after `setlastProcessedZxid` | `msg.lastZxid` (dense floor of DataTree lastProcessedZxid) |
| TruncateLog | TRUNC branch after `setlastProcessedZxid` | `state.recovered`, `msg.lastZxid` |
| ApplySyncCommit | COMMIT branch after in-memory `zk.processTxn` (writeToTxnLog false) | `msg.tx`, `msg.lastZxid` |
| QueueForSync / FlushTxnLog | `SyncRequestProcessor.processRequest` (enqueue + emit under lock) / `flush` after `commit()` | `state.queue` = that processor's unflushed modeled requests; Flush `msg.leaked` |
| FollowerPendingProposal / FollowerCommit | `FollowerZooKeeperServer.logRequest` / `commit` | `state.pending` = real `pendingTxns` |
| RecordProposalAck / CommitProposal | `Leader.processAck` / `tryToCommit` | `state.acks` / `state.commitWitness` = real ack set |
| ApplyTxn | `FinalRequestProcessor.applyRequest` | `msg.lastZxid` |
| Begin/FinishSnapshot | `ZooKeeperServer.takeSnapshot(syncSnap)` | `msg.syncSnap`, `msg.lastZxid` |

To add a field: extend the relevant `SpeculaTrace` method and the matching wrapper in `spec/Trace.tla`, then regenerate the patch with `git -C artifact add -N <new files> && git -C artifact diff > harness/patches/instrumentation.patch`.

Known capture limits: the snapshot base of `recovered` assumes a snapshot contains every modeled txn at or below its zxid (true without lost proposals in the harness scenarios); TRUNC/in-sync COMMIT and leaked flushes of queued writes are timing-dependent and were not observed.
