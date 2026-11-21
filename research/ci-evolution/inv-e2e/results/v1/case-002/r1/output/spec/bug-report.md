# Bug Report — Apache ZooKeeper Zab, incremental run (baseline -> update)

Source under test: `artifact/` commit `update` (2efbdfc3754df193bce05b9792297c813377cdaf).
Persistence detail (MC-1 argument): `FileTxnLog.append` writes into a
`BufferedOutputStream` (FileTxnLog.java:287-288) and only `commit()` flushes and
forces it (FileTxnLog.java:375-385); queued SyncRequestProcessor requests are
in-memory, so a process crash loses both.
Old-version control: `old-control/` worktree at `baseline`
(1414ebfb1d16fd81abc38550a96950d919ecf805).

## Summary

- Scenarios tested: 6 (V0 Scenarios 1-4, update Scenarios 5-6)
- Bugs found: 2 (MC-1, MC-2), both affecting the update's changed path
  (`Learner.syncWithLeader` NEWLEADER handling) and its interactions
- Configs with violations: `Update-concrete.cfg`, `Update-open.cfg`,
  `Update-concrete2-A2.cfg`, `Update-concrete2-A2-crash.cfg` (all reproduced on the
  final reference: runs Z3, Z3b, Z3c; rev-B runs R3, R3b, R3c); real-trace violations on
  `traces/diff-sync-consistency.ndjson` and `traces/repro-initial-state-failure.ndjson`
- Reproduction: MC-2 reproduced on the updated implementation and on the baseline
  control (`harness/repro/`).

## Bug 1: NEWLEADER ACK precedes durability of synchronized records (MC-1)

- **Scenario**: 5 (NEWLEADER ACK versus durability of synchronized records)
- **Severity**: High
- **Invariant violated**: `CommittedPersistedOnQuorum` (window) and
  `LeaderCompleteness` (loss after a learner crash)
- **Config**: `Update-concrete.cfg` (A1, runs Z3/R3) and `Update-concrete2-A2-crash.cfg`
  (A2 crash variant, runs Z3c/R3c)
- **Counterexample**: `spec/output/mc-Z3-update-concrete-A1.log` (final reference;
  rev-B: `mc-R3-update-concrete-A1.log`), `spec/output/mc-Z3c-update-concrete2-A2-crash.log`
  (final; rev-B: `mc-R3c-update-concrete2-A2-crash.log`);
  real-trace window: `spec/evidence/trace-A1/tlc.log`

### Trace Summary

From `FocusInit` (s1 holds an uncommitted epoch-1 record t1; reachable from
`MCInit`, witness `spec/output/mc-C6-reach-focusinit-sim.log`):

1. s1 is elected, proposes epoch 2, persists it, enters SYNCHRONIZATION.
2. Learner s2 gets DIFF `<t1>` (buffered in `packetsNotCommitted`), persists
   current epoch 2, clears sync mode, starts its server INITIAL, hands t1 to
   `logRequest` (queued only) and writes the NEWLEADER ACK.
3. s1 receives the ACK; with its own ACK this is a quorum, so `startZkServer`
   serves its loaded database containing t1 (state 20: t1 committed and served,
   persisted only on s1) — `CommittedPersistedOnQuorum` fails.
4. Crash variant: s2 completes UPTODATE, s1 steps down, s2 crashes before its
   SyncThread appends/forces t1; s2 restarts with current epoch 2 and an empty
   log, wins FLE against s3 (higher peer epoch), and activates epoch 3 without
   t1 — `LeaderCompleteness` fails: a transaction already served as committed is
   gone from the new leader's history.

The window was observed on the real updated implementation:
`traces/diff-sync-consistency.ndjson` events 87-98 (learner s1: ProposalQueued
0x100000002 at 90, NewLeaderAckSent at 91; leader s2 activates at 94; s1's
TxnDurable for 0x100000002 only at 98), and `traces/follower-diff.ndjson` events
12-20.

### Root Cause

`Learner.syncWithLeader` (L:743-760) persists the new epoch, then calls
`FollowerZooKeeperServer.logRequest` (FZK:82-89), which only enqueues into the
SyncRequestProcessor (SRP:291-297); the record is appended to a buffered stream
and forced later on the SyncThread (SRP:181-249, `FileTxnLog` commit). The ACK of
NEWLEADER (L:760) is written immediately, but the leader treats a NEWLEADER-ACK
quorum as the commit of its entire history (LH:613-624, Ldr:1546-1586,
Ldr:1497-1537). ZooKeeper's own protocol description requires an ACK to mean the
proposal is on persistent storage (zookeeperInternals.md:116-119, 192-197); the
update's comment (L:748) states the same intent.

### Affected Code

- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:743-760`: epoch persisted and ACK written before the queued records are forced
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:82-89`: `logRequest` only enqueues
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:181-249`: asynchronous append/flush
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:1497-1586`: activation on the NEWLEADER-ACK quorum

### Recommendation

Make the learner wait until the records handed to the SyncRequestProcessor at
NEWLEADER are forced before acknowledging NEWLEADER (and preferably before
persisting the new current epoch), e.g. a synchronous flush barrier on the
SyncRequestProcessor.

---

## Bug 2: learner failure between NEWLEADER and UPTODATE hides logged committed records (MC-2)

- **Scenario**: 6 (learner failure in the INITIAL server state)
- **Severity**: Critical (committed data lost without any process crash; reproduced)
- **Invariant violated**: `LeaderCompleteness`
- **Config**: `Update-concrete2-A2.cfg` (runs Z3b/R3b; also `hunt-A2-from-focus2`)
- **Counterexample**: `spec/output/mc-Z3b-update-concrete2-A2-initial.log` (final
  reference; rev-B: `mc-R3b-update-concrete2-A2-initial.log`; from FocusInit2 =
  final state of the MC-1 A1 counterexample);
  real-trace violation `spec/evidence/trace-A2/tlc.log`

### Trace Summary

1. As in Bug 1 steps 1-3: leader s1 serves t1 after a NEWLEADER-ACK quorum
   {s1, s2}; learner s2's server is INITIAL with t1 queued.
2. s2's learner fails before UPTODATE (socket timeout / leader unreachable):
   `Learner.shutdown` -> `LearnerZooKeeperServer.shutdown` returns immediately
   because `canShutdown()` is false for INITIAL, so `fastForwardDataBase` is not
   run; s2's data tree still lacks t1 (its leaked SyncThread may still log t1).
3. s2 (current epoch 2, data-tree zxid without t1) and s3 elect s2; s2 loads its
   in-memory database (lacking t1) and activates epoch 3: `LeaderCompleteness`
   fails although no server crashed.

### Reproduction (implementation)

`harness/repro/SpeculaInitialStateFailureReproTest.java` (derived from the
update's `DIFFSyncConsistencyTest`: learners fail right after reading UPTODATE;
the old leader is stopped once it serves the DIFF-synchronized `/zkL`; learners
are NOT restarted). Run: `SPECULA_SCENARIOS=repro-initial-state-failure bash harness/run.sh`.

- Updated implementation: FAILS (attempt 3, `spec/output/repro-surefire-update.txt`,
  `spec/output/repro-surefire-update-summary.txt`): the old leader served
  `/zk2`; after it stopped, server 1 led epoch 5 and both remaining servers'
  in-memory databases lack `/zk2`; real clients connected to server 0 and to
  server 1 repeatedly get `exists("/zk2") = null` ("Data inconsistency: committed
  /zk2 served by the old leader is missing from the new leader's database").
  Its instrumented trace `traces/repro-initial-state-failure.ndjson` (494 events)
  replays against the final reference (`Trace-conformance.cfg`, TraceMatched) and
  violates `LeaderCompleteness` right after event 139 (`ZkStartup s1 RUNNING`:
  epoch-3 activation without 0x100000002) and `CommittedHistoriesPrefix` right
  after event 211 (`LeaderCommitted s1 0x500000001` at the position where the
  old leader had committed 0x100000002): `spec/evidence/trace-A2/`.
  Earlier attempts (`traces/superseded-run1/repro-*`) show the same outcome.
- Baseline control: also FAILS the same way (`spec/output/old-control-repro.log`:
  new leader epoch 3 lacks /zk2; client `exists` returns null). The mechanism
  pre-dates the update; the update's fix (logging at NEWLEADER) only helps when
  the failed learner process restarts and reloads its log, as in
  `DIFFSyncConsistencyTest`. Control note: `DIFFSyncConsistencyTest` itself
  passes on the baseline in this environment too
  (`spec/output/old-control-diffsync-test.log`), so it does not discriminate the
  revisions here.

### Root Cause

The update starts the learner's server in INITIAL state at NEWLEADER
(L:751, ZKS:673-696) and only reaches RUNNING after UPTODATE (L:765-767,
ZKS:677-680). A failure in between leaves `ZooKeeperServer.canShutdown()` false
(ZKS:784), so `LearnerZooKeeperServer.shutdown` (LZK:155-173) skips both the
processor shutdown and `zkDb.fastForwardDataBase()` (ZKS:845). The DIFF records
are applied only after UPTODATE (`packetsCommitted`, L:783-785), so the data tree
used for the FLE vote (`QuorumPeer.getLastLoggedZxid`, QP:1257-1262) and loaded
by a new leader (`ZooKeeperServer.loadData`, ZKS:499-503) omits them. After a
leader activation the marker `lastProcessedZxid = (epoch,0)` (Ldr:1536) also
stops later fast-forwards from replaying them (FileTxnSnapLog.java:317-333).

### Affected Code

- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:751-767`: INITIAL server between NEWLEADER and UPTODATE; DIFF records applied only after UPTODATE
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java:784-851`: `canShutdown`/`shutdown` skip fast-forward for INITIAL
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerZooKeeperServer.java:155-173`
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:1257-1262`: vote basis is the in-memory data tree
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java:480-512`: leader keeps the initialized in-memory database

### Recommendation

On any learner exit after NEWLEADER processing, bring the in-memory database in
line with the log (shut down/flush the started processors and fast-forward even
from INITIAL, or clear the database so it is reloaded), and ensure the vote zxid
reflects every acknowledged record.

---

## Not Reproduced / campaign results

See `spec/output/validation-summary.md` for the full campaign table (states,
depth, budget status). Summary on the final reference:

| Scenario | Config | Result |
|---|---|---|
| Standard convergence | `MC.cfg` | see validation-summary (budget-limited, LIMITED_COVERAGE) |
| 1 Election | `MC-hunt-election.cfg` | see validation-summary |
| 2 Sync | `MC-hunt-sync.cfg` | see validation-summary |
| 3 Pipeline | `MC-hunt-mutation.cfg` | see validation-summary |
| 4 Recovery | `MC-hunt-recovery.cfg` | see validation-summary |
| 5 NEWLEADER durability | `Update-concrete.cfg`, `Update-open.cfg`, `Update-concrete2-A2-crash.cfg` | violations (MC-1) |
| 6 INITIAL-state failure | `Update-concrete2-A2.cfg` | violation (MC-2) |

## Spec fixes during checking

- Case B: `SyncDiff` admitted a learner ahead of the leader's committed log
  (MC.cfg C1, depth 38, `ServingApplyCommitted`); repaired per LH:845-853.
- Trace-driven: fast-forward floor after leader activation (repro attempt-1
  event 167). Both recorded in `spec/changelog.md`.
