# Bug Report — ZooKeeper Zab, incremental case-010 (`baseline` f8533cd -> `update` b16ba71)

## Summary

- Update disposition: MODEL_CHANGE_REQUIRED (model updated; see `analysis-report.md` §Incremental).
- The update's target behavior is confirmed: an unfinished **SNAP** sync now clears the reused in-memory database (`fully=true`, `dbInitialized=false`, reload from disk) and the update's own test passes on the new code and fails on the old code. Within the checked bounds, the SNAP-only isolation view finds no violation for the new code and finds one for the old code.
- Scenarios tested: U1 (unfinished SNAP sync), U2 (unfinished TRUNC sync), U3 (serving learner shutdown no longer drains its sync processor), plus all inherited V0 scenarios.
- Bugs found: 2 (MC-1 reproduced on the real implementation; MC-2 mechanism observed in real traces, data-consistency consequence shown by the model only).
- Configs run: see `spec/output/verification-summary.md` (all model-checking runs are bounded: LIMITED_COVERAGE, not proof).

## Bug 1: Unfinished TRUNC sync keeps unlogged committed transactions in the reused in-memory database (SNAP-only fix misses TRUNC)

- **ID**: MC-1
- **Scenario**: U2 (sibling branch of the update's changed predicate)
- **Severity**: High
- **Invariant violated**: `UpdIdleDbBackedByDisk` (precursor); `OrderedHistories` / `UpdDurableCoversCommitted` (consequence, observed in the real reproduction trace)
- **Config**: `spec/Update-focused-txn1.cfg` (CodeVersion `new`, MaxTxn 1, 2 learner exits)
- **Counterexample**: 38 steps, `spec/output/counterexamples/MC-1-trunc-abort-update-focused-txn1.log` (+ `.cex.tla`); independently found by the complete reference `MCNext` (`spec/Update-full.cfg`, 38 steps): `spec/output/counterexamples/MC-1-trunc-abort-update-full-MCNext.log`
- **Status**: reproduced on the updated implementation and on the old implementation (pre-existing; not fixed by the update) — `harness/repro/SpeculaTruncAbortReproTest.java`, `spec/output/repro/trunc-abort-new.out`, `spec/output/repro/trunc-abort-old.out`

### Trace Summary

1. Leader s1 and follower s2 reach broadcast. s1 proposes txn 1; s2 logs and flushes it (its ACK is sent or lost), s1 commits txn 1 but has not yet applied it (`toBeApplied`).
2. s2 loses its leader connection while serving (`LearnerExit`); `zk.shutdown(false)` fast-forwards s2's database from its log, so s2 reports txn 1 as its last zxid.
3. s2 rejoins the same leader. Leader-side `syncFollower` sees the learner's zxid above its max committed log and chooses **TRUNC** to the earlier zxid; `startForwarding` queues txn 1 from `toBeApplied` as PROPOSAL+COMMIT before NEWLEADER.
4. s2 truncates txn 1 from its log and reloads, then (TRUNC keeps `snapshotNeeded = true`, so `writeToTxnLog = false`) applies the COMMIT for txn 1 **only in memory**.
5. s2's sync fails before the NEWLEADER snapshot (`LearnerExit`). `syncMode == TRUNC`, so `fullyShutDown` is false and the database is **not** cleared: in memory s2 holds committed txn 1, its disk does not → `UpdIdleDbBackedByDisk` violated.
6. (Real reproduction, continued) s2 rejoins with an empty DIFF (its in-memory zxid equals the leader's), logs txn 2 on top of a log without txn 1 (`OrderedHistories` violated at replay state 95 of `traces/repro-trunc-abort-new.ndjson`), and after a restart from disk node 1 is missing on s2 while present on the leader: `node1AfterRestart=false node2AfterRestart=true node1OnLeader=true`.

### Root Cause

- `Learner.syncWithLeader` sets `snapshotNeeded = false` only for DIFF (Learner.java:560-564); for TRUNC it stays true, so `writeToTxnLog = !snapshotNeeded` is false (Learner.java:614) and COMMITs received before NEWLEADER are applied with `zk.processTxn` without logging (Learner.java:656-666). They become durable only through `zk.takeSnapshot` at NEWLEADER (Learner.java:738-741).
- The update forces a full shutdown only when `self.getSyncMode().equals(SNAP)` (Learner.java:862-864). For TRUNC, `ZooKeeperServer.shutdown(false)` returns early because the server is not running (ZooKeeperServer.java:803-810), so the in-memory database is kept and `QuorumPeer.getLastLoggedZxid` reports it (QuorumPeer.java:1257-1262).
- The leader then sends an empty/short DIFF (LearnerHandler.java:843-850), so the missing committed transaction is never resent and later log appends create a hole (`FileTxnLog.append` accepts any zxid, FileTxnLog.java:274-282).

### Affected Code

- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:862-864`: SNAP-only `fullyShutDown` predicate.
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:554-614,656-666,738-750`: TRUNC applies COMMITs in memory before the NEWLEADER snapshot.
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java:803-810`: early-return path that now clears only when `fullyShutDown`.
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerHandler.java:853-861,920`; `Leader.java:1289-1305`: TRUNC decision and `toBeApplied` forwarding before NEWLEADER.

### Recommendation

Force the full shutdown (database clear) whenever the learner may hold unpersisted synchronized state, i.e. for every sync mode that applies transactions in memory before the NEWLEADER snapshot (SNAP **and** TRUNC), or track an explicit "in-memory state not yet persisted" flag set at the mode packet and cleared after `takeSnapshot`.

---

## Bug 2: `Learner.shutdown` now bypasses `LearnerZooKeeperServer.shutdown()`; the learner `SyncRequestProcessor` is never stopped or drained

- **ID**: MC-2
- **Scenario**: U3 (update-introduced)
- **Severity**: Medium
- **Invariant violated**: `OrderedHistories` (the learner log holds txn 2 without txn 1)
- **Config**: `spec/Update-focused.cfg` (CodeVersion `new`, MaxTxn 2) and isolation view `spec/Update-leak-new.cfg`; old-code control `spec/Update-leak-old.cfg`
- **Counterexample**: 35 steps, `spec/output/counterexamples/MC-2-leaked-sync-processor-update-focused.log` (+ `.cex.tla`)
- **Status**: mechanism observed on the real implementation (every serving `LearnerShutdown` in the fresh new-code traces reports `syncAlive=true`; the old-code control reports `false`); the log-gap consequence needs the leaked thread's flush to be delayed past a re-sync and was not reproduced.

### Trace Summary

1. Leader s1 proposes txns 1 and 2; follower s2 queues both in its `SyncRequestProcessor` and flushes txn 1; txn 2 is still queued.
2. s2's leader connection fails while serving (`LearnerExit`). New code: `zk.shutdown(false)` runs `ZooKeeperServer.shutdown(boolean)`; the learner sync processor is not shut down, so txn 2 stays in a still-running processor (`leakedQueued`).
3. s2 rejoins; its reported zxid (txn 1) is above the leader's max committed log, so the leader chooses TRUNC and s2 truncates txn 1 from its log.
4. The leaked processor now appends and flushes txn 2 into the reopened transaction log (`LeakedFlush`): s2's log holds txn 2 without txn 1 → `OrderedHistories` violated. In the old code the processor was drained during `Learner.shutdown`, before the TRUNC, so the truncation removed both.

### Root Cause

- Old: `Learner.shutdown` called `zk.shutdown()`, dispatched to `LearnerZooKeeperServer.shutdown()` (LearnerZooKeeperServer.java:155-173), which after `super.shutdown()` calls `syncProcessor.shutdown()` (enqueue death marker, join, flush; SyncRequestProcessor.java:254-270). `ObserverZooKeeperServer.shutdown()` does the same (ObserverZooKeeperServer.java:131-141).
- New: `zk.shutdown(self.getSyncMode().equals(SNAP))` (Learner.java:864) dispatches to `ZooKeeperServer.shutdown(boolean)` (ZooKeeperServer.java:803-859), which neither learner subclass overrides. The learner sync processor thread therefore survives every learner shutdown: it blocks in `queuedRequests.take()` forever (SyncRequestProcessor.java:166-170) — one leaked thread per serving-follower disconnect — or appends its remaining queue later through `zks.getZKDatabase().append` into the shared `FileTxnSnapLog`, whose `txnLog` is reopened by `truncateLog`.

### Attribution (old-code control)

`Update-leak-old.cfg` (CodeVersion `old`, same isolation view) also reaches `OrderedHistories` (42 steps, `spec/output/counterexamples/control-old-preuptodate-leak-update-leak-old.log`), through a **pre-existing** variant: a learner whose session fails after NEWLEADER but before UPTODATE already leaves the sync processor started by `startupWithoutServing` (Learner.java:751) running in the old code, because `canShutdown()` is false and `LearnerZooKeeperServer.shutdown()` returns early. The update extends the leak from that pre-UPTODATE window to every serving learner shutdown (the common case), where the old code drained and stopped the processor; the serving-shutdown path is the update-introduced part (`syncAlive`: new `true`, old `false` in the same real scenario).

### Realizability notes

- Deterministic part (observed): the leaked processor thread. With an empty queue it blocks in `queuedRequests.take()` forever; each serving-follower (or observer) disconnect leaks one `SyncThread` plus its references to the old server and database.
- Racy part (model only): `Learner.shutdown` closes the leader socket first (`closeSockSync` sets `sock = null`), so a leaked processor that tries to ACK after the close throws a `NullPointerException` in `SendAckRequestProcessor` (`learner.sock.isClosed()`, SendAckRequestProcessor.java:47-52) and exits via `handleException`. A queued proposal is therefore written after a TRUNC only if the thread dequeues and appends it without first ACKing anything after the close, while stalled across the re-election — a narrow window (e.g., the thread starved between dequeue and append). The model does not represent this NPE exit (`LeakedFlush` may fire any time); the counterexample is a possible, not a typical, interleaving.

### Affected Code

- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:864`
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerZooKeeperServer.java:155-173`
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/ObserverZooKeeperServer.java:131-141`
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java:803-859`

### Recommendation

Override `shutdown(boolean)` in `LearnerZooKeeperServer` (and `ObserverZooKeeperServer`) so the learner sync processor is stopped and drained on every path (or have `Learner.shutdown` call a learner-specific method that preserves both the drain and the new `fullyShutDown` behavior).

---

## Not Reproduced / No Violation (bounded)

| Scenario | Config | Result |
|---|---|---|
| U1 SNAP abort, new code | `Update-snapfix-new.cfg`, `Update-e2e-snap-new.cfg` | No violation within the time-bounded BFS (LIMITED_COVERAGE); see verification summary |
| U1 SNAP abort, old code (control) | `Update-snapfix-old.cfg`, `Update-focused-old.cfg` | `UpdIdleDbBackedByDisk` violated (old behavior; matches the diff's own test failing on old code) |
| U3 leak, old code (control) | `Update-leak-old.cfg` | see verification summary |
| Inherited V0 properties, standard round | `MC.cfg` (MCCoreNext) | exhaustive, no violation |

## Spec fixes during validation/hunting

See `spec/changelog.md` (Round 1/2): leader-side `LeaderDecideSync`, pre-NEWLEADER commit cut, `syncComplete` timing at learner shutdown, atomic `setPeerState(LOOKING)`.
