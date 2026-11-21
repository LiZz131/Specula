# Bug Report — ZooKeeper Zab (incremental case-010, source `update` b16ba71)

## Summary

- Scenarios tested: U1 (SNAP-window learner exit, changed), U2 (TRUNC-window learner exit, sibling branch; crash-free and crash-based variants), U3 (DIFF exit after NEWLEADER), plus the V0 regression scenarios through the standard/full/wide configs and the rebased inherited hunts.
- Bugs found: 2 model-checking findings against the **updated** source (model-checking evidence plus source analysis; real-system reproduction is Part 4 and was not run):
  - **MC-1** (High): TRUNC-mode learner exit keeps a non-durable in-memory commit — the update's full shutdown covers SNAP only. Same mechanism as the update's fix, on its sibling branch; pre-existing and not fixed by the update.
  - **MC-2** (High): DIFF-mode learner that exits after NEWLEADER but before UPTODATE under-reports its own log; a record it logged (and possibly ACKed) is invisible to the next election, leaving a never-committed record below committed ones in its log. Pre-existing; not related to the update's changed condition.
- Differential controls (exact-old learner exit, `UpdateFullShutdownOnSnap = FALSE`) reproduce the defect class the update fixes; they are non-vacuity evidence, not findings.
- All results are on the final model (after the repairs listed at the end); campaign outcomes are in `spec/output/verification-summary.md`.

## Bug 1: TRUNC-mode learner exit keeps a non-durable in-memory commit; the update's full shutdown covers only SNAP

- **Scenario**: U2 (crash-free variant U2b) — modeling-brief.md section 8.3
- **Severity**: High (a committed record can be missing from a learner's disk while the learner reports it; after an empty-DIFF resync the hole is permanent and survives restart; the learner's ACKs still count toward later commit quorums)
- **Invariant violated**: `ReportedHistoryDurable` (Update.tla); consequence `DurableHistoryConsistent` (base.tla)
- **Config**: `spec/Update-hunt-mc1-deterministic.cfg` (FocusNext with `ACTION_CONSTRAINT SnapSteerDeterministicCommit`, 3 peers, no crash, 2 learner exits, MaxTxn 2); consequence: `spec/Update-continue-mc1-consequence.cfg` (INIT = reachable final state of the witness, MaxTxn 3)
- **Counterexample**: final model: 55 states, `spec/output/counterexamples/MC-1-witness-deterministic-commit-final.log` (TLC log `spec/output/final4-update-hunt-mc1-deterministic-bfs.log`); consequence: 19 further states, `spec/output/counterexamples/MC-1-consequence-durable-hole-final.log` (cfg `spec/Update-continue-mc1-consequence.cfg`, module `spec/UpdateContinueMC1.tla`). Earlier witnesses on intermediate model revisions are kept for lineage (`MC-1-witness-deterministic-commit.log`, `MC-1-reported-history-not-durable-trunc.log`).

### Trace Summary

Final-model witness (55 states, `spec/output/counterexamples/MC-1-witness-deterministic-commit-final.log`). Peers s1 (leader), s2, s3; epoch 1; records 1, 2 (ids in zxid order). Every ACK used comes from a flush that precedes the sender's exit.

1. States 1-27: s1 leads epoch 1 with s2 (DIFF sync); s1 proposes records 1 and 2.
2. 28-35: s2 logs and flushes records 1 and 2 (its ACKs are sent by `SendAckRequestProcessor` after the flush).
3. 36: s2 exits while serving (read timeout / I/O error): `Learner.shutdown` -> server RUNNING -> sync processor drained, `fastForwardDataBase`; data tree `<<1,2>>` = disk `<<1,2>>`.
4. 37-49: s1 records the ACKs and commits records 1 and 2 (quorum {s1, s2}) but has applied only record 1 (committed-log max = 1); s2 becomes LOOKING and rejoins s1.
5. 50-51: s2 reports zxid 2 > maxCommittedLog 1, so `LearnerHandler.syncFollower` chooses **TRUNC to 1**; s2 truncates its txn log — record 2, which s2 itself helped commit, leaves s2's disk.
6. 52-53: because record 2 was committed but not applied at the decision, `startForwarding` queued its PROPOSAL and COMMIT before NEWLEADER; in TRUNC mode `writeToTxnLog` is false, so the COMMIT is applied **only in memory**: data tree `<<1,2>>`, disk `<<1>>`.
7. 54-55: s2 fails before handling NEWLEADER (the fault the update's own test injects for SNAP). `Learner.shutdown` passes `fullyShutDown = (TRUNC == SNAP) = false`; the server is not running, so `shutdown(false)` returns early and the data tree keeps record 2. s2 is LOOKING and reports `lastLoggedZxid = 2` with only record 1 on disk -> `ReportedHistoryDurable` violated.

Consequence (continuation from the reachable final state of this witness, 19 further states, `spec/output/counterexamples/MC-1-consequence-durable-hole-final.log`, `DurableHistoryConsistent` violated): the learner rejoins; the leader has applied record 2, so `peerLastZxid == lastProcessedZxid` and it sends an **empty DIFF**; DIFF NEWLEADER takes no snapshot, so record 2 is never re-persisted; the learner logs record 3 and ACKs it (counted in record 3's commit quorum). Its disk becomes `<<1,3>>` while `<<1,2,3>>` is committed (its ACKs are in the quorums of records 2 and 3): after a restart it replays a history without record 2, and record 2 is durable only on the leader although the learner's ACK completed its quorum.

### Root Cause

TRUNC sync uses the same "apply in memory until the NEWLEADER snapshot" regime as SNAP: `snapshotNeeded` stays true for TRUNC (`Learner.java:555,564`), so `writeToTxnLog = !snapshotNeeded` is false (`Learner.java:614`) and a COMMIT read before NEWLEADER is applied with `zk.processTxn` without logging (`Learner.java:656-665`); durability is only restored by `zk.takeSnapshot` at NEWLEADER (`Learner.java:739-741`). The update makes a learner exit discard that non-durable data tree only when `syncMode == SNAP` (`Learner.java:861-865`, `ZooKeeperServer.java:803-810`). A TRUNC-mode exit still takes the early return (`ZooKeeperServer.java:784-786,804-809`), and the next `getLastLoggedZxid` (`QuorumPeer.java:1257-1262`) reports the in-memory record. TRUNC is reached without any crash when a learner reports a record the leader has committed but not yet applied (`LearnerHandler.java:853-863`), and `Leader.startForwarding` puts that record's PROPOSAL and COMMIT ahead of NEWLEADER (`Leader.java:1289-1302`; `LearnerHandler.java:551-600`). The truncation removes the record from the learner's log because only snapshots survive `truncateLog` (`ZKDatabase.java:599-611`; `FileTxnSnapLog.java:502-524`).

Attribution: the path crosses the updated action (`LearnerShutdown`) and is exactly the mechanism the update repairs for SNAP; the TRUNC branch behaves as in the old revision (old code never cleared). The defect is therefore pre-existing and **not fixed by the update** (incomplete coverage of the updated mechanism), not introduced by it.

### Affected Code

- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:864`: full shutdown conditioned on `SyncMode.SNAP` only.
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:555-614,656-665`: TRUNC keeps `snapshotNeeded`, so pre-NEWLEADER COMMITs are memory-only.
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java:803-810`: clear only when `fullyShutDown`.
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerHandler.java:853-863`: TRUNC for a learner ahead of maxCommittedLog (includes committed-but-unapplied records).
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:1289-1302`: toBeApplied PROPOSAL+COMMIT queued before NEWLEADER.

### Recommendation

Discard the data tree on a learner exit whenever the sync had applied records in memory without logging them, i.e. whenever `snapshotNeeded` was true and the NEWLEADER snapshot has not completed (SNAP **and** TRUNC), e.g. `zk.shutdown(syncMode == SNAP || syncMode == TRUNC)`, or track "in-memory-only state present" explicitly instead of keying on the sync mode. Not validated against an implementation; reproduction (Part 4) should use the update test's NEWLEADER fault with a TRUNC sync.

---

## Bug 2: DIFF learner exiting between NEWLEADER and UPTODATE under-reports its log; a logged record escapes the next epoch

- **Scenario**: U3 (DIFF exit after NEWLEADER, adjacent unchanged path) — modeling-brief.md section 8.3
- **Severity**: High (a server's own log can contain a record that the next epoch's history does not contain; after its restart its data tree diverges from the ensemble; if the record had been committed with that server's ACK, the next leader can lack a committed record)
- **Invariant violated**: `DurableHistoryConsistent` (base.tla); `LeaderCompleteness` variant under investigation (`spec/output/final4-update-hunt-mc2-leadercompleteness-sim.log`)
- **Config**: `spec/Update-hunt-trunc-steered2.cfg` (FocusNext with `ACTION_CONSTRAINT TruncSteer2`, 1 crash, 1 extra round, 1 injected exit, MaxTxn 3), simulation
- **Counterexample**: 89 states, `spec/output/counterexamples/MC-2-diff-window-uncommitted-record-in-log.log` (TLC log `spec/output/final4-update-hunt-trunc-steered2-sim.log`)

### Trace Summary

1. States 1-32: s1 leads epoch 1 with s3; s1 proposes record 1 (outstanding).
2. 33-36: late joiner s2 is sent a (empty) DIFF; `startForwarding` queues the outstanding PROPOSAL(1) before NEWLEADER; s2 buffers it.
3. 37-44: s1 proposes record 2 and logs records 1, 2 only locally; s2 handles NEWLEADER (setCurrentEpoch); s1 crashes.
4. 45-53: s2 finishes the NEWLEADER handler: `setSyncMode(NONE)`, `startupWithoutServing` (sync processor started), `logRequest(1)`; writing the NEWLEADER ACK fails and s2 exits. The server never reached RUNNING, so `shutdown(false)` returns early: the data tree (never updated in DIFF before UPTODATE) stays empty, while the already-started sync processor keeps running and flushes record 1 to s2's log.
5. 54-76: s2 reports zxid 0 (its data tree), ties with s3, and is elected leader of epoch 2; `Leader.lead -> zk.loadData` keeps the in-memory database, so epoch 2's history does not contain record 1; s3 syncs with an empty DIFF.
6. 77-89: s2 proposes record 3, both log it, it commits. s2's disk is `<<1,3>>` with record 1 never committed below committed record 3 -> `DurableHistoryConsistent` violated. On s2's restart record 1 is replayed (the leader-start snapshot is taken at zxid 0, `ZooKeeperServer.java:480-511`), so s2's data tree diverges from s3's.

### Root Cause

In DIFF mode the learner logs buffered proposals at NEWLEADER (`Learner.java:751-757`) but applies nothing to the data tree until after UPTODATE (`Learner.java:777-785`); `startupWithoutServing` (`Learner.java:751`) starts a sync processor that flushes and ACKs those records (`SendAckRequestProcessor.java:40-63`). An exit before UPTODATE finds the server not RUNNING, so `ZooKeeperServer.shutdown(false)` returns early (`ZooKeeperServer.java:784-786,804-809`): neither the processors are stopped nor the database fast-forwarded. `getLastLoggedZxid` (`QuorumPeer.java:1257-1262`) then reports the stale data tree, below what the server has logged. Elections and `LearnerHandler.syncFollower` trust that value, so the next epoch may be built without the logged record while the record stays in this server's log. The update's condition (`syncMode == SNAP`) is false here in both revisions (`syncMode` is NONE after NEWLEADER, DIFF before it), so the behaviour is pre-existing and unrelated to the change.

### Affected Code

- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:751-760`: logs and ACKs at NEWLEADER without updating the data tree.
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java:804-809`: early return leaves processors running and the database un-fast-forwarded.
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:1257-1262`: reported zxid read from the data tree, not the log.

### Recommendation

On a learner exit after `startupWithoutServing`, stop the started processors and either fast-forward the database from the log or clear it so that the next `getLastLoggedZxid` reloads disk (for example request a full shutdown whenever records were logged but not applied). Not validated against an implementation.

---

## Differential controls (not findings)

| Control | Config | Result |
|---|---|---|
| U1 property non-vacuity (exact-old exit) | `Update-hunt-snap-steered-oldcontrol.cfg` | `ReportedHistoryDurable` violated at depth 39 (learner keeps SNAP image after exit) — `spec/output/final4-update-hunt-snap-steered-oldcontrol-bfs.log` |
| U1 consequence non-vacuity (exact-old exit) | `Update-hunt-snap-steered-oldcontrol-consequence.cfg` | `DurableHistoryConsistent` hole (disk `<<2>>` while `<<1,2>>` committed) at depth 55 on the pre-FIFO-repair model (`spec/output/update-hunt-snap-steered-oldcontrol-consequence-bfs-predrainfix.log`); final-model rerun: `spec/output/final4-update-hunt-snap-steered-oldcontrol-consequence-bfs.log` |
| Trace-level (exact-old model vs real updated trace) | `Trace-oldsemantics-control.cfg` | rejected at the changed event (line 173) |

## Spec fixes during hunting

See `spec/changelog.md` Round 3: ApplyTxn only on serving servers (Case B), TRUNC keeps snapshot-covered records (`snapZ`, Case B — the first SNAP-steered counterexample relied on the faulty truncation and was discarded), no ACKs from the shutdown drain (Case B), NEWLEADER FIFO cut for proposals read before NEWLEADER (Case B), steering vote constraint fix (vacuous schedules re-run). MC-1 and MC-2 were re-established after the last repair.
