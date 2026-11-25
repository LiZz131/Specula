# Bug Report — Apache ZooKeeper Zab, incremental run (`1414ebf` → `2efbdfc`)

## Summary

- Update disposition: MODEL_CHANGE_REQUIRED (model updated; see `../analysis-report.md`).
- Scenarios tested: U-1..U-4 (update) + inherited V0 Scenarios 1-4.
- Model-checking findings: 3 (MC-1, MC-2 update-related; MC-3 update-independent).
- Supplementary real-implementation reproductions: MC-1 (fault-injected crash before fsync),
  MC-2 (in-process re-election), MC-3 (learner side); each fails on the update revision and on
  the old baseline control (none is introduced by the update; MC-1/MC-2 cross the updated
  NEWLEADER path, which narrows MC-1 but closes neither).
- Configs run: see "Campaign outcomes" (all runs are budget-limited explorations, not proofs).

The two update-related findings show that the update's intended guarantee — a NEWLEADER-ACK
quorum certifies that the synchronized history is held by the acknowledging learners
("make sure sync the uncommitted logs before commit them (ACK NEWLEADER)",
`quorum/Learner.java:747`) — is not established by the new code.

---

## Bug 1: NEWLEADER ACK is sent before the logged sync proposals are durable (MC-1)

- **Scenario**: U-1 (NEWLEADER ACK versus learner durability)
- **Severity**: High
- **Invariant violated**: `LeaderCompleteness` (consequence); mechanism property
  `NewLeaderAckImpliesDurable`
- **Config**: `Update-hunt-crash-window.cfg` (`FocusSpec` from the reachable checkpoint
  `FocusInit`; one crash, no role exit)
- **Counterexample**: 28 states, `output/mc-final-hunt-crash-window-bfs.log`
  (+ `.cex.json`); checkpoint prefix: 16 states, `output/mc-checkpoint-witness-r2.log`.
  Mechanism-only counterexample (property U3):
  full model from `MCInit` (simulation): `output/mc-final-update-full-sim.log`.

### Trace Summary
1. Checkpoint (reachable from `MCInit`, witness r2): s1 led epoch 1, proposed t1 = (1,1) while
   no follower was connected, logged it durably and left the role; nobody else has t1.
2. s1 is elected for epoch 2 (vote of the learner); the learner DIFF-syncs: t1 is buffered
   in `packetsNotCommitted` (`SyncWithLeader`).
3. NEWLEADER: epoch persisted, `startupWithoutServing` (INITIAL), `logRequest(t1)` →
   SyncRequestProcessor queue only (`LearnerLogPendingOne`), then ACK (`LearnerSendNewLeaderAck`)
   — `durable[learner] = <<>>`, `queued[learner] = <<t1>>`.
4. s1 counts the ACK, `startZkServer`: t1 becomes committed and served (`maxCommitted = <<t1>>`).
5. The learner process crashes before the SyncThread appends/fsyncs t1; it restarts with an
   empty log/tree (`Crash`, `Restart`).
6. With s1 partitioned (still LEADING epoch 2), the learner (currentEpoch 2) and the third
   server elect the learner for epoch 3; the third server DIFF-syncs (empty) and ACKs.
7. The epoch-3 leader starts serving without t1 → `LeaderCompleteness` violated: a txn that a
   leader served after its NEWLEADER quorum is missing from a later leader.

### Root Cause
`FollowerZooKeeperServer.logRequest` only enqueues the request to the SyncRequestProcessor
(`quorum/FollowerZooKeeperServer.java:82-90`; append/flush on the SyncThread,
`SyncRequestProcessor.java:155-251`).  `Learner.syncWithLeader` writes the NEWLEADER ACK right
after the enqueue loop (`quorum/Learner.java:752-760`) without waiting for the flush; the
leader treats a NEWLEADER-ACK quorum as permission to serve its whole history
(`quorum/Leader.java:661-688`, `:1497-1536`).
Real-execution evidence: in the fresh `follower-diff` trace the learner ACKs at seq 13 while
`TxnDurable` for the same zxid appears only at seq 21; replaying the validated real traces
`follower-diff`, `diff-sync-uptodate-failure` and the reproduction trace through the model
violates `NewLeaderAckImpliesDurable` (`output/trace-update-props-summary.txt`).

### Real-implementation reproduction (supplementary)
`harness/repro/AckBeforeFsyncReproTest.java`: DIFFSyncConsistencyTest setup; follower txn-log
appends stall (slow disk), then a stalled append fails without writing (crash before fsync)
and the followers are restarted from disk while the old leader is stopped.  Control logic: if
the leader does not serve while appends are stalled (an implementation that waits for
durability before the ACK), the stall is released first and the test passes.
- update revision (`spec/output/repro-ackfsync-new-1.log`): old leader served `/zk2` while the
  followers' appends were stalled; the new leader (epoch 3) lacks `/zk2` — assertion fails.
- baseline control `1414ebf` (`spec/output/repro-ackbeforefsync-old-1.log`): same failure
  (the old code did not even queue the txn before the ACK).  The update narrows but does not
  close the window.

### Affected Code
- `quorum/Learner.java:752-760`: logRequest loop then ACK(newLeaderZxid) without a flush barrier
- `quorum/FollowerZooKeeperServer.java:82-90`: asynchronous `logRequest`
- `SyncRequestProcessor.java:155-251`: batching/flush on the SyncThread
- `quorum/Leader.java:661-688`: serving after the NEWLEADER-ACK quorum

### Recommendation
Make the NEWLEADER ACK wait until the requests logged at NEWLEADER are fsynced (e.g. a
synchronous flush of the SyncRequestProcessor, or append+commit through the txn log before
writing the ACK).

---

## Bug 2: a learner that fails between NEWLEADER and UPTODATE keeps a stale DataTree; an in-process re-election loses the served txn (MC-2)

- **Scenario**: U-2 (UPTODATE failure after the ACK, shutdown skipped in INITIAL)
- **Severity**: High
- **Invariant violated**: `LeaderCompleteness` (also `CommittedAgreesWithQuorumHistory`,
  `AckedHistoryRetained`)
- **Config**: `Update-hunt-reelection.cfg` (`FocusSpec` from `FocusInit`; one role exit,
  no crash)
- **Counterexample**: 27 states, `output/mc-final-hunt-reelection-bfs.log` (+ `.cex.json`);
  checkpoint prefix `output/mc-checkpoint-witness-r2.log`.

### Trace Summary
1. Checkpoint as in Bug 1 (t1 logged only at s1).
2. s1 elected for epoch 2; learner s3 DIFF-syncs, logs t1 at NEWLEADER (state INITIAL) and
   ACKs; s1 starts serving t1 (`maxCommitted = <<t1>>`).
3. s3's read of UPTODATE fails (socket timeout / network) → `ServerShutdown` with
   `zkState = INITIAL`: `canShutdown()` is false, so neither `fastForwardDataBase` nor the
   processor shutdown runs; s3's DataTree stays at its pre-sync position (t1 absent) while its
   leaked SyncRequestProcessor keeps the logged t1.
4. s3 advertises its DataTree zxid (`QuorumPeer.getLastLoggedZxid`) and, with currentEpoch 2,
   wins epoch 3 with the third server's vote while s1 is partitioned.
5. `Leader.lead → loadData` reuses the initialized (stale) tree; the third server DIFF-syncs
   (nothing) and ACKs; s3 starts serving epoch 3 without t1 → `LeaderCompleteness` violated.
   (s3's txn log still holds t1, so a later restart replays it: replicas diverge.)

### Root Cause
`ZooKeeperServer.startupWithoutServing` (new) leaves the follower instance in `State.INITIAL`
with processors running (`ZooKeeperServer.java:669-704`, `quorum/Learner.java:748-751`).
`LearnerZooKeeperServer.shutdown` and `ZooKeeperServer.shutdown` return immediately unless
`canShutdown()` (RUNNING/ERROR) (`quorum/LearnerZooKeeperServer.java:155-159`,
`ZooKeeperServer.java:784-807`), so the DataTree is not fast-forwarded from the log.  The
election vote, FOLLOWERINFO/ACKEPOCH and `Leader.lead` use the DataTree position
(`quorum/QuorumPeer.java:1257-1262`, `ZooKeeperServer.java:480-503`).  The new test
(`DIFFSyncConsistencyTest`) restarts every follower process, which reloads the log and hides
the in-process path.

### Real-implementation reproduction (supplementary)
`harness/repro/StaleTreeReelectionReproTest.java` (same setup as DIFFSyncConsistencyTest, but
only the old leader is stopped and the followers re-elect in-process):
- update revision (`spec/output/repro-new-1.log`, trace
  `traces/repro-stale-tree-reelection-1.ndjson`): old leader served `/zk2` in epoch 2; new
  leader 1 (epoch 4) does not have `/zk2` — assertion fails.  The trace replays through
  `Trace.tla` (`output/trace-final2-repro-stale-tree-reelection-1.log`), and the replay
  violates `LeaderCompleteness` at state 158, `AckedHistoryRetained` at 121
  (`output/trace-update-props-repro-stale-tree-reelection-1-*.log`).
- old baseline control `1414ebf` (`spec/output/repro-old-1.log`): same failure.  The in-process
  loss is therefore **not fixed** by the update (pre-existing mechanism, path crosses the
  updated NEWLEADER actions); in the new revision the txn additionally remains in the
  learners' logs and resurfaces on restart.

### Affected Code
- `quorum/Learner.java:744-760` (startupWithoutServing + ACK) and `:762-767` (startServing)
- `quorum/LearnerZooKeeperServer.java:155-173`, `ZooKeeperServer.java:784-850` (canShutdown guard)
- `quorum/QuorumPeer.java:1257-1262`, `ZooKeeperServer.java:480-503` (tree-based zxid/history)

### Recommendation
Do not let a learner that already logged the synchronized history leave with a stale tree:
shut down (drain + fast-forward) an INITIAL instance whose processors were started, or reload
the database before re-entering LOOKING, and make the ACK durable (Bug 1).

---

## Bug 3: TRUNC to a zxid absent from the learner's log keeps the next entry (MC-3, update-independent)

- **Scenario**: inherited Scenario 2 (DIFF/TRUNC/SNAP) — not affected by the update
- **Severity**: Medium
- **Invariant violated**: `ServingApplyRequiresCommitCertificate`
- **Config**: `Update-focus-trunc.cfg`
- **Counterexample**: 15 states, `output/mc-final-focus-trunc-bfs.log`

### Trace Summary
From the checkpoint, s2 (empty tree) is elected for epoch 2 by s2+s3 while s1 (log and tree
hold the uncommitted t1 = (1,1)) is partitioned.  s1 then joins s2: `LearnerHandler.syncFollower`
has an empty committed log, so `maxCommittedLog = lastProcessedZxid = 0` and
`peerLastZxid (1,1) > 0` → TRUNC 0 (`quorum/LearnerHandler.java:836-861`).
`FileTxnLog.truncate(0)` keeps every entry up to the first one with zxid ≥ 0, i.e. it keeps
(1,1) (`persistence/FileTxnLog.java:455-475`, iterator `:624-670`); `ZKDatabase.truncateLog`
reloads it into the tree and `setlastProcessedZxid(0)` (`quorum/Learner.java:588-598`).
After UPTODATE the learner serves t1, which no leader committed.

### Real-implementation reproduction (supplementary)
`harness/repro/TruncAbsentZxidReproTest.java` (real Learner/ZKDatabase/FileTxnLog, scripted
leader sending exactly LearnerHandler's TRUNC 0): `spec/output/repro-trunc-new-1.log` — after
TRUNC 0 the log tail is still 0x100000001, the tree has lastProcessedZxid 0 and contains
`/orphan`.  Baseline control `1414ebf`: same result (`spec/output/repro-truncabsentzxid-old-1.log`).

### Recommendation
Truncate strictly after the target zxid (keep only entries ≤ target), including when the
target precedes every logged entry.

---

## Code-review item (not model-checked)

CR-1 — processors started at NEWLEADER can emit per-txn ACKs (SendAckRequestProcessor) before
the NEWLEADER ACK; `LearnerHandler` treats the first ACK as the NEWLEADER ACK
(`quorum/LearnerHandler.java:611-623`) and `Leader.waitForNewLeaderAck` ignores a mismatched
zxid (`quorum/Leader.java:1555-1563`).  Availability only (leader may miss its quorum and
re-elect).  Not observed in fresh traces (`NewLeaderAckRejected` count 0); the FIFO learner
channel is outside the model.

---

## Campaign outcomes

See `../spec/output/campaign-summary.md` (generated after the final runs).

## Spec fixes during checking

- [fix-spec, Case B] vote lifetime: `WinElection` reused votes from earlier rounds;
  votes are now consumed on a win and withdrawn on role exit/crash.
- [fix-spec, Case B from real trace] `ServerShutdown` fast-forwards from the DataTree's
  `lastProcessedZxid` (`LastLogged`), not from the last tree entry.
- [fix-inv, Case A] `OneActiveLeaderPerEpoch` counts epoch-bound leaders only.
