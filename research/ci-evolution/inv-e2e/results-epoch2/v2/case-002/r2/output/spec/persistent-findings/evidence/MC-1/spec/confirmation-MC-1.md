# Confirmation MC-1: NEWLEADER ACK precedes durability of DIFF-synced transactions

- **Source**: model checking (actual counterexamples, see `spec/bug-report.md`
  §Bug 1): `CommittedQuorumDurable` violated in `Update-hunt-durable.cfg`
  (`output/mc/update-hunt-durable-final.log`, 26 states, 3 servers) and
  `Update-hunt-durable-2s.cfg` (`output/mc/update-hunt-durable-2s-r3.log`, final
  model) and the full-reference check `Update-full.cfg`
  (`output/mc/update-full-bfs-r3.log`, final model, 26 states); consequence `CommittedNeverLostByLeader` violated by the continuation
  hunt `Update-hunt-loss-witness.cfg` (`output/mc/update-hunt-loss-witness-r3.log`:
  the acking learner crashes before its fsync, a new leader is elected without
  the old one, and the old leader's only durable copy is truncated by TRUNC).
  Corroborated by a fresh real-execution trace and a reproduction on the
  updated implementation.
- **Revision under test**: artifact commit `2efbdfc` ("update"), uninstrumented
  copy `repro/work-new`; old control `1414ebf` ("baseline"), `repro/work-old`.
- **Novelty**: NEW within this run's inputs (no persistent finding matched:
  `specular findings lookup --query SyncWithLeaderNewLeader --query CommittedQuorumDurable --query syncWithLeader` → `[]`).
- **Status**: **REPRODUCED** (escalation level 1: test-fixture timing assistance
  + SIGKILL-equivalent crash images; no system logic changed).
- **Severity**: High (a transaction that a leader already served to clients is
  absent at the next leader: lost committed write / divergent view).

## Phase 1 — investigation

Code path (updated source, `zookeeper-server/src/main/java/org/apache/zookeeper/server/`):

1. `quorum/Learner.java:743` persists the new current epoch.
2. `quorum/Learner.java:749-757` starts the learner server without serving and
   calls `FollowerZooKeeperServer.logRequest` for each buffered proposal;
   `quorum/FollowerZooKeeperServer.java:86-88` only adds it to `pendingTxns`
   and to `SyncRequestProcessor.queuedRequests` (`SyncRequestProcessor.java:277`).
3. `quorum/Learner.java:760` writes the NEWLEADER ACK immediately; nothing
   waits for `SyncRequestProcessor.flush` → `ZKDatabase.commit` (fsync,
   `SyncRequestProcessor.java:227-246`).
4. `quorum/LearnerHandler.java:611-623` → `quorum/Leader.java:1547-1573`
   counts the ACK; once a quorum is counted, `Leader.lead` starts serving
   (`Leader.java:663-712`) its whole loaded history (including transactions
   that were only on the leader's disk).
5. A learner process crash before its SyncThread fsync loses the transaction;
   if the old leader is unavailable, the remaining quorum elects a leader
   without it.

Developer intent: the update's comment "make sure sync the uncommitted logs
before commit them (ACK NEWLEADER)" (`Learner.java:748`) and its test
`DIFFSyncConsistencyTest` ("Data inconsistency detected!", lines 128-133,
204-214) state the guarantee; `zookeeperInternals.md:117-119` defines ACK as
persistent recording. The update's own test passes because an exception (not a
process crash) is injected: the failed learner's `ZooKeeperServer` is still
INITIAL, its shutdown is skipped, and its leaked SyncThread finishes the fsync
(fresh trace `traces/diff-sync-uncommitted-log.ndjson`, events 84-93: s1
`ProposalQueued (1,2)` → `NewLeaderAck` → `TxnAppended` → leader
`NewLeaderAckCounted s1` → leader `PhaseChanged broadcast` → s1 LOOKING →
`TxnDurable (1,2)`). `CommittedQuorumDurable` evaluates FALSE on the replayed
state after event 90 (`spec/evidence/E1-CQD/tlc.log`).

## Phase 2 — reproduction

Test: `repro/NewLeaderAckDurabilityReproTest.java` (copy in `spec/evidence/repro/`), driver
`repro/test_bug1_newleader_ack_before_fsync.sh`, matrix `repro/run-all-bug1.sh`.

- Same preparation as `DIFFSyncConsistencyTest` (leader alone fsyncs `/zk<L>`).
- Level 1 timing assistance: a test-fixture `ZKDatabase` subclass holds the
  learners' `commit()` (flush + fsync) for at most 15 s — a slow disk. No
  ZooKeeper code is modified.
- Crash emulation: when the leader first serves `/zk<L>`, each learner's data
  directory is copied. FileTxnLog keeps un-committed txn bytes in its Java
  `BufferedOutputStream`, so the copy is exactly what survives a SIGKILL at
  that instant. All servers are stopped; learners restart from the images
  without the old leader.

Commands: `repro/test_bug1_newleader_ack_before_fsync.sh new 3 hold15s ""` etc.
(each Maven run under `timeout 900s`). Summary (`repro/logs/bug1-summary.log`):

| revision | variant | runs | leader served /zk2 while learner fsync held | new leader has /zk2 | result |
|---|---|---|---|---|---|
| new 2efbdfc | hold 15 s + crash images | 3 | yes (1096-1930 ms after restart, `held_commits=2`) | **no** | FAIL: `Data inconsistency detected! /zk2 was served by the old leader but is missing at new leader 1` |
| new 2efbdfc | control: hold, no crash (normal shutdown) | 1 | yes | yes | pass (the leaked/normal SyncThread finishes the fsync) |
| new 2efbdfc | natural timing (hold 0) + crash images | 3 | gate not held; fsync on this fast disk completed first | yes | pass (window not hit without a slow disk) |
| old 1414ebf | hold 15 s + crash images | 2 | yes | **no** | FAIL (pre-existing; the old code logged the DIFF txns only after UPTODATE) |
| old 1414ebf | control: hold, no crash | 1 | yes | yes | pass |

Output excerpt (`repro/logs/org.apache.zookeeper.server.quorum.NewLeaderAckDurabilityReproTest-output-new-hold15s-run1.txt`):

```
REPRO served /zk2 at 1930 ms after learner restart; learner fsync gate still held: true; held commits: 2
REPRO-OBSERVATION restore_images=true hold_ms=15000 served_ms=1930 gate_held_at_serve=true held_commits=2
REPRO-OBSERVATION new_leader=1 has_/zk2=false
```

Match with the counterexample: same actions in the same order —
leader-only durable entry, re-election, DIFF `CompleteSync`,
`SyncWithLeaderNewLeader` (queued, not durable), `LeaderBroadcast` with the
NEWLEADER ack quorum, crash of the acking learners before `FsyncOne`,
re-election without the old leader → `CommittedQuorumDurable` /
`CommittedNeverLostByLeader` / `CommittedHistoriesPrefix` violated.

Attribution: the update narrowed but did not close a pre-existing window (old
code: until after UPTODATE; new code: until the asynchronous fsync completes).
A fix would make the NEWLEADER ACK wait until the logged proposals are durable
(e.g. synchronously append+commit them before the ACK, or send the ACK from the
SyncRequestProcessor after the flush).
