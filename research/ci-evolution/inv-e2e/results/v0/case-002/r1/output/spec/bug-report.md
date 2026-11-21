# Bug Report — Apache ZooKeeper Zab, incremental update (case-002)

Source: `artifact/` commit `update` (2efbdfc3754d). Model: `spec/base.tla`, `spec/MC.tla`,
`spec/Update.tla` (final artifacts). Every counterexample below is a behaviour of the complete
`MCNext` (hunt configs add only state constraints that restrict exploration).

## Summary

- Scenarios tested: inherited V0 Scenarios 1-4 (election, sync, pipeline, recovery) plus update
  Scenarios U-NPE, U-DUR, U-EPOCH, U-LOSS.
- Bugs found (actual model-checking counterexamples): 3 (MC-1, MC-2, MC-3).
- Configs run: see the campaign table in `spec/output/mc-summary.md`.

## Bug 1: NullPointerException when a COMMIT crosses NEWLEADER (MC-1)

- **Scenario**: U-NPE
- **Severity**: High
- **Invariant violated**: `Update!NoSyncException`
- **Config**: `spec/Update-hunt-npe.cfg` (depth 34) and `spec/Update-hunt-npe-strict.cfg` (depth 38)
- **Counterexample**: `spec/output/mc/hunt-update-npe-strict.log`, `spec/output/cex/hunt-update-npe-strict.json`
- **Also found without guidance**: random simulation of `spec/Update-full.cfg` (full MCNext, symmetric, no constraint) violated `NoSyncException` after 45 traces (59-state trace): `spec/output/mc/sim-update-full.log`, `spec/output/cex/sim-update-full.json`

### Trace Summary
s1 is elected (epoch 1) and s2 synchronises and enters BROADCAST. s3 joins late: `SelectSync`
(DIFF) forwards s1's outstanding proposal t1 into s3's stream, then `LeaderQueueNewLeader`.
s3 buffers PROPOSAL t1, processes NEWLEADER (`LearnerNewLeader`,
`LearnerStartupWithoutServing`, `LearnerLogPending` — buffer cleared — `LearnerAckNewLeader`).
s2 forces and ACKs t1; `Commit(s1, t1)` appends COMMIT t1 to s3's stream after NEWLEADER;
`LearnerCommit(s3)` finds `packetsNotCommitted` empty -> NullPointerException, sync aborted.

### Root Cause
`quorum/Learner.java:752-757` (update) clears `packetsNotCommitted` at NEWLEADER, while the
unchanged COMMIT handler (`Learner.java:643-646`) dereferences `packetsNotCommitted.peekFirst()`.
`Leader.startForwarding` (Leader.java:1294-1330) forwards outstanding proposals before
`LearnerHandler` queues NEWLEADER (LearnerHandler.java:591-601), so a COMMIT may legally follow
NEWLEADER for a proposal received before it.

### Affected Code
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:643-646`: unguarded dereference
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:752-757`: buffer cleared at NEWLEADER

### Recommendation
Do not dereference the buffer head for a plain COMMIT after NEWLEADER (only record it for
`fzk.commit`), and stop the INITIAL-state processors on failure. Confirmation: REPRODUCED
(new 3/3 fail, old control passes) — `spec/confirmation-MC-1.md`.

---

## Bug 2: NEWLEADER ACKed and currentEpoch persisted before the synchronised history is durable (MC-2)

- **Scenario**: U-DUR / U-EPOCH
- **Severity**: High
- **Invariant violated**: `Update!EpochHistoryRecoverable` (crash clause); `Update!NewLeaderAckDurable`
- **Config**: `spec/Update-hunt-epoch.cfg` (depth 30); `spec/Update-hunt-dur.cfg` (depth 38)
- **Counterexample**: `spec/output/mc/hunt-update-epoch.log` / `spec/output/cex/hunt-update-epoch.json`;
  `spec/output/mc/hunt-update-dur.log` / `spec/output/cex/hunt-update-dur.json`

### Trace Summary
Epoch 1: s1 leads with s2, proposes t1 and forces it locally only. Epoch 2: s1 re-elected with s3;
s3 receives PROPOSAL t1, COMMIT t1, NEWLEADER; `LearnerNewLeader` persists currentEpoch 2 while t1
is still only in `packetsNotCommitted`/the SyncRequestProcessor queue; s3 crashes -> its persisted
state has currentEpoch 2 and no t1 (an FLE winner by epoch over servers holding t1). In the
U-DUR trace, `LearnerAckNewLeader` sends the ACK the leader counts while t1 is queued but not forced.

### Root Cause
`Learner.java:739-760`: `setCurrentEpoch` precedes logging, and the update only enqueues the
buffered proposals (`FollowerZooKeeperServer.logRequest`) before the ACK; the force happens later in
`SyncRequestProcessor.flush`. Pre-existing in the old revision (ACK before any logging).

### Affected Code
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:739-760`
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:82-89`

### Recommendation
Force the synchronised proposals before persisting the new epoch and before ACKing NEWLEADER.
Confirmation: ENV_LIMITED (window demonstrated deterministically, crash not injectable) —
`spec/confirmation-MC-2.md`.

---

## Bug 3: Stale tree after a failure in the new INITIAL state; in-process re-election loses a committed transaction (MC-3)

- **Scenario**: U-LOSS (and U-EPOCH looking clause)
- **Severity**: Critical
- **Invariant violated**: `Update!LeaderCompleteness` (no crash; depth 49)
- **Config**: `spec/Update-hunt-loss-tight.cfg` (MaxCrash = 0)
- **Counterexample**: `spec/output/mc/hunt-update-loss-tight.log`, `spec/output/cex/hunt-update-loss-tight.json`

### Trace Summary
Epoch 1: s1 leads (s2 ACKs NEWLEADER), proposes t1, forces it, then leaves the role (drain +
fast-forward). Epoch 2: s1 re-elected with s3; s3 synchronises t1 (DIFF), persists epoch 2,
starts in INITIAL, queues t1, ACKs NEWLEADER; s1 counts the ACK. s3's session fails before UPTODATE
(`BeginElection` from INITIAL: no shutdown, no fast-forward -> tree still empty). s3 wins epoch 3
over s2 (higher currentEpoch), syncs s2 with an empty history and establishes epoch 3, while s1
establishes epoch 2 and commits/serves t1: the epoch-3 leader's history lacks the committed t1.

### Root Cause
`ZooKeeperServer.startupWithServerState(State.INITIAL)` (ZooKeeperServer.java:669-704, update) plus
the unchanged `canShutdown()` guard (ZooKeeperServer.java:784-805, LearnerZooKeeperServer.java:155-174):
a learner failing between NEWLEADER and UPTODATE is not shut down, its tree is not fast-forwarded,
and `getLastLoggedZxid()`/`zk.loadData()` keep using the stale tree with the new current epoch.

### Affected Code
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java:669-704,784-805`
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerZooKeeperServer.java:155-174`
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:739-767`

### Recommendation
On any failure after NEWLEADER, stop the processors and reload/fast-forward the database before
the next election. Confirmation: REPRODUCED (`/zk2` committed and served by the old leader is
missing after in-process failover; new 3/3, old control fails too) — `spec/confirmation-MC-3.md`.

---

## Not Reproduced

See `spec/output/mc-summary.md` for every campaign, its bounds, depth, state counts and stop reason
(all BFS runs stop at the per-run time budget with a non-empty queue: LIMITED_COVERAGE, not proof).

| Scenario | Config | States explored | Result |
|---|---|---|---|
| V0 1-4 reference safety (ElectionSafety, OneActiveLeaderPerEpoch, CommittedHistoriesPrefix, ApplyRequiresCommitCertificate, PipelinePrefix, EpochHistoryConsistency, SyncCompletionJustified, HistoryPositionsMonotonicExceptRecovery) | `MC.cfg` (BFS round 2 + simulation) | 20,335,614 distinct, depth 29 (queue non-empty) | No violation within budget (after the Case A revision of PipelinePrefix) |
| Update + reference properties, full MCNext, unguided | `Update-full.cfg` BFS | 10,916,717 distinct, depth 29 | No violation within budget (update violations need depth >= 30; the simulation follow-up found MC-1) |
| Concrete focused (Affected \/ Interaction) | `Update-focused.cfg` | 6,319,632 distinct, depth 27 | No violation within budget |
| Open focused (with EnvUpdate) | `Update-open.cfg` | 3,272,330 distinct, depth 22 | No violation within budget |
| Discharge of omitted context (TakeSnapshot, DropMessage) | `Update-discharge.cfg` | 3,898,355 distinct, depth 25 | No violation within budget |
| U-LOSS with crashes instead of INITIAL exit | `Update-hunt-loss-crash-tight.cfg` | 9,106,406 distinct, depth 38 | Not reached within budget (target ~52 steps); crash consequence covered by MC-2 |
| U-LOSS random simulation | `Update-hunt-loss-sim.cfg` | ~46k traces | Not reached (BFS with tighter guidance found it, MC-3) |

Spec fixes during hunting: `PipelinePrefix` snapshot clause (Case A), see `spec/changelog.md` Round 2.
