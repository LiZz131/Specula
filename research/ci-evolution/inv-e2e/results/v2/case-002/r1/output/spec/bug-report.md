# Bug Report — Apache ZooKeeper Zab, incremental run on the updated source

Source under test: artifact commit `update` 2efbdfc3754df193bce05b9792297c813377cdaf
(change to `Learner.syncWithLeader` NEWLEADER/UPTODATE handling and
`ZooKeeperServer.startupWithoutServing/startServing`). Prior exact-old suite:
`/work/previous/.specula-output` (no findings).

## Summary

- Update scenarios: U1 (ACK vs durability), U2 (crash in window), U3 (post-NEWLEADER
  COMMIT; code-review route), U4 (aborted sync in the INITIAL window), plus all
  prior scenarios as regression.
- Model-checking findings: **3** (MC-1, MC-2 update-related; MC-3 pre-existing in
  unchanged learner shutdown code, exposed by the trace-driven model refinement). Code-review finding with direct
  code observation: **1** (CR-1, recorded in `modeling-brief.md` section 8 and
  `spec/final-result.json`, not in `findings.json`, per the findings format).
- Every campaign outcome: `spec/output/update/campaign-summary.md`.

## Bug 1: NEWLEADER quorum commits a history that is not durable on a quorum

- **Scenario**: U1 / U2
- **Severity**: High
- **Invariant violated**: `CommittedDurableOnQuorum` (state) and `NewLeaderAckDurable` (action)
- **Config**: `spec/Update-focused-quorumdurable.cfg`, `spec/Update-focused-ackdurable.cfg`
- **Counterexample**: 13 states, `spec/output/update/final-focused-quorumdurable.log`
  (summary `cex-final-focused-quorumdurable.txt`); 12 states,
  `spec/output/update/final-focused-ackdurable.log`.

Independent full-model witness: simulation of the complete `MCSpec` from
`MCInit` (`Update-full.cfg`, `final-sim-update-full.log`) also violates
`NewLeaderAckDurable` (epoch-1 leader logs T1, is re-elected in epoch 2 and
DIFF-synchronizes a learner that ACKs NEWLEADER before persisting T1).

### Trace Summary

From the epoch-1 aftermath (only the old leader s1 has T1 durable; the
initial-state family is reachable from `MCInit`, witness
`final-reach-recovery-shape.log`):
1. s1 wins epoch 2; follower s2 registers and is synchronized with DIFF; the
   stream T1 is buffered (`ReceiveSyncPayload`).
2. s2 persists currentEpoch=2 and clears its sync mode, then `AckNewLeader`:
   T1 is only enqueued to the SyncRequestProcessor (`queued[s2]=<<T1>>`,
   `durable[s2]=<<>>`) while ACK(NEWLEADER) is sent and counted by s1.
3. `LeaderBroadcast(s1)`: the NEWLEADER quorum {s1, s2} activates epoch 2 and
   commits T1, which is durable only on s1 (CommittedDurableOnQuorum false).

The same transition is observed in the REAL updated implementation:
`traces/follower-diff.ndjson` event 12 (`NewLeaderAckSent`, logged=1,
durableZxid=-1, i.e. no txn log on disk; the txn becomes durable at event 18,
after the learner already served and applied it), the observation test
(`traces/update-observe-ack-durability.ndjson.observation.json`:
`streamedDurableWhenNewLeaderAckReceived=false`), and the visible-diff test run
(`traces/update-diff-sync-consistency.ndjson` events 82-89: leader s2 counts
s0's ACK (84) and activates (86) before s0's TxnDurable (89)). The action-level
replay `TraceSync.tla` reaches the violating state from the real trace
(`final`/`tracesync-ackwitness-follower-diff-final.log`, `NotAckBeforeDurable`).

A crash of the acknowledging learners inside this window (U2) discards the
queued T1 (`Crash` drops non-durable records) and a later quorum without T1
can elect a leader whose history omits the committed T1
(`final-hunt-postact-crash.log` finds LeaderCompleteness violations from the
post-activation state; the shortest path it reports is the crash-free U4 path
of Bug 2).

### Root Cause

`Learner.syncWithLeader` NEWLEADER branch (new-source Learner.java:749-760):
`fzk.logRequest(...)` only calls `syncProcessor.processRequest(request)`
(FollowerZooKeeperServer.java:81-88, enqueue into `queuedRequests`); append and
`FileTxnLog.commit()` (flush+force) happen later on `SyncThread`
(SyncRequestProcessor.java:166-250). `writePacket(ACK newLeaderZxid, true)`
follows immediately, and `Leader.waitForNewLeaderAck` (Leader.java:1547-1585)
counts it; after the quorum `startZkServer` serves the leader history
(Leader.java:663-712). The stated contract of the change (Learner.java:757,
"make sure sync the uncommitted logs before commit them (ACK NEWLEADER)") and
the protocol documentation (zookeeperInternals.md:119 "Acknowledgement means
the server has recorded the proposal to persistent storage", :194, :196-197)
require persistence before the ACK. The exact-old code ACKed before even
enqueueing (old-semantics model control `final-oldcontrol-*` and
`old-control/old-newLeaderAckPrecedesDurability.observation.json`): the update
narrows but does not close the window.

### Affected Code

- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:749-760`: logRequest enqueue then immediate ACK(NEWLEADER)
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:81-88`: logRequest is asynchronous
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:166-250`: durability only at flush
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:1547-1585`: NEWLEADER ACK counted as synced

### Recommendation

Make the NEWLEADER-logged records durable before writing ACK(NEWLEADER)
(e.g. flush/force the transaction log synchronously for those records, or send
the ACK from the SyncRequestProcessor after the flush that covers them).

---

## Bug 2: aborted synchronization after the NEWLEADER ACK loses a committed transaction

- **Scenario**: U4 (and U2)
- **Severity**: High
- **Invariant violated**: `LeaderCompleteness`
- **Config**: `spec/Update-hunt-postact-leak.cfg` (no crash), `spec/Update-hunt-postact-crash.cfg`
- **Counterexample**: 14 states, `spec/output/update/final-hunt-postact-leak.log`
  (summary `cex-final-hunt-postact-leak.txt`), from the reachable
  post-activation state (= final state of Bug 1's counterexample).

### Trace Summary

Initial state: epoch-2 leader s3 has activated and committed T1 after counting
learner s2's NEWLEADER ACK; s2 holds T1 only in its SyncRequestProcessor queue
(INITIAL server state); s1 is LOOKING in epoch 1.
1. s2's synchronization aborts before UPTODATE (`BeginElection(s2)` from the
   SYNCHRONIZATION phase). Because the server is not RUNNING, `zk.shutdown()`
   is a no-op: the database is not fast-forwarded (`memHist[s2]` lacks T1) and
   the started SyncRequestProcessor keeps running.
2. s1 votes for s2 (currentEpoch 2 > 1); s2 wins epoch 3 and loads its
   in-memory database WITHOUT T1 (`recovered[s2]=<<>>`).
3. s1 follows s2, DIFF-synchronizes (empty), ACKs NEWLEADER; s2 activates
   epoch 3 (`LeaderBroadcast`) serving a history that omits T1, which epoch 2
   committed (certEpoch=2) and leader s3 served.

The real updated implementation executed this path in the visible-diff test
(`traces/update-diff-sync-consistency.ndjson`): after the injected UPTODATE
failure, s1 goes LOOKING (103-104), its leaked `SyncThread:1` makes
0x100000002 durable afterwards (105) and then dies with "Severe unrecoverable
error ... NullPointerException: this.learner.sock is null" (surefire log line
1318); s1 starts an election proposing zxid 0x100000001 (in-memory), wins
epoch 3 with s0 (106-120) and activates epoch 3 (126) while epoch-2 leader s2,
which activated with 0x100000002 at event 86 and served `/zk0` to the test
client, is still LEADING (until 131-134). The test passes only because the
full restart that follows (135+) reloads 0x100000002 from disk; until then the
epoch-3 leader serves an older view, and its own log contains 0x100000002
below its epoch-3 history.

### Root Cause

- `ZooKeeperServer.startupWithoutServing()` (ZooKeeperServer.java:673-675,
  682-698) starts all request processors but leaves the state INITIAL.
- Any failure between NEWLEADER and UPTODATE runs `Learner.shutdown -> zk.shutdown()`;
  `LearnerZooKeeperServer.shutdown` (155-172) and `ZooKeeperServer.shutdown(boolean)`
  (803-807) return immediately because `canShutdown()` is false for INITIAL
  (784-786): processors are neither stopped nor flushed and
  `zkDb.fastForwardDataBase()` (834-850) is skipped.
- FLE and ACKEPOCH report `getLastLoggedZxid()` (in-memory) and a new leader
  serves `zk.loadData()`'s in-memory database (Leader.java:593), so the
  peer's durable copy of the committed txn is invisible to election and
  synchronization.

### Affected Code

- `zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java:673-698`: startupWithoutServing leaves state INITIAL with processors running
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java:784-807`: shutdown skipped for INITIAL
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerZooKeeperServer.java:155-172`: sync processor not shut down
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:749-767`: NEWLEADER starts processors, UPTODATE switches to RUNNING

### Recommendation

When synchronization aborts after `startupWithoutServing()`, shut the started
processors down (drain and flush the SyncRequestProcessor) and fast-forward the
in-memory database before the peer re-enters leader election, e.g. by allowing
the learner shutdown path for the INITIAL state once processors were started.

---

## Bug 3 (pre-existing, exposed by the refined model): learner leave persists a proposal outside the next leader's history

- **Scenario**: U4 interaction (unchanged learner shutdown path)
- **Severity**: High
- **Invariant violated**: `SyncedLogMatchesLeader` (revised formulation, see `spec/invariant-evidence.json` E5/E5c/E5g)
- **Config**: `spec/Update-hunt-ghost.cfg` (focused), admitted by `spec/Update-hunt-ghost-full.cfg` (full MCNext)
- **Counterexample**: 19 states, `spec/output/update/final-hunt-ghost.log` (full: `final-hunt-ghost-full.log`)

### Trace Summary

From the reachable state where the epoch-2 leader s3 activated after both
learners ACKed NEWLEADER (witness `final-reach-bothacked.log`, 21 steps from
RecoveryInit):
1. learner s2 completes UPTODATE (RUNNING); learner s1 aborts (INITIAL, MC-2 path).
2. s3 proposes T2; s2 receives it (queued, not yet flushed).
3. s2 leaves FOLLOWING while RUNNING: `ZooKeeperServer.shutdown` fast-forwards
   the in-memory database from the durable log (without T2), THEN the learner's
   SyncRequestProcessor is shut down and flushes T2 to disk.
4. s1 (in-memory history without T1/T2) wins epoch 3 with s2's vote; s2
   reports its stale in-memory zxid, receives an empty DIFF and enters
   BROADCAST while its log holds T2, an uncommitted epoch-2 proposal unknown to
   its leader (a restart would replay it into s2's database).

### Root Cause

`LearnerZooKeeperServer.shutdown()` (LearnerZooKeeperServer.java:155-172) calls
`super.shutdown()` - which ends with `zkDb.fastForwardDataBase()`
(ZooKeeperServer.java:834-850) - before `syncProcessor.shutdown()` drains and
flushes queued requests. FLE and ACKEPOCH then report
`QuorumPeer.getLastLoggedZxid()` = `zkDb.getDataTreeLastProcessedZxid()`
(QuorumPeer.java:1257-1262, Learner.java:487, FastLeaderElection.java:869),
and `LearnerHandler.syncFollower` chooses DIFF from that stale position, so the
leader never tells the learner to discard the persisted proposal
(zookeeperInternals.md:182-183). This code is unchanged by the update
(identical in `/work/old-source`-era tree); the update adds the INITIAL-window
variant of the same divergence (Bug 2: no fast-forward at all).

### Affected Code

- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerZooKeeperServer.java:155-172`: fast-forward before sync-processor flush
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:1257-1262`: in-memory position reported to FLE / registration

### Recommendation

Shut down and flush the learner's SyncRequestProcessor before fast-forwarding
the database (as the leader's processor chain already does), so the reported
position includes every persisted record.

---

## Not Reproduced / budget-limited

| Scenario | Config | States explored | Result |
|---|---|---|---|
| see campaign summary | `spec/output/update/campaign-summary.md` | per run | per run |

## Spec adjustments during this run

Case A/B repairs (trace-driven `memHist`, leave/flush semantics, removal of
unfaithful prior actions, capture-timing and interpretation fixes) are listed
in `spec/changelog.md` Round I1; none weakened a requirement property.
