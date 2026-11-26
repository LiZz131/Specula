# Bug Report — ZooKeeper Zab, case-002 update (run incr-8c80add29fe2)

## Summary

- Scenarios tested: prior Scenarios 1-4 plus update Scenarios US-1..US-3 (modeling-brief.md, "Incremental update").
- Model-checking bugs found: 1 (MC-1), with two violated update properties (U2 mechanism, U3 consequence).
- Code-review candidates confirmed separately: CR-1, CR-2, CR-3 (see `spec/confirmation-*.md`).
- All counts below are bounded TLC explorations (LIMITED_COVERAGE), never proofs.

## Bug 1: NEWLEADER ACK is sent before the DIFF-synchronized history is durable

- **Finding id**: MC-1
- **Severity**: High (loss of a transaction that a leader already served after its NEWLEADER quorum)
- **Invariants violated**: `NewLeaderAckDurable` (U2) and `CommittedSurvivesLeaderChange` (U3), `spec/UpdateProps.tla`
- **Configs**: `Update-seed-focused-U2.cfg`, `Update-seed-focused-U1U3.cfg` (spec `UpdateSeed.tla`, `NewLeaderLogsPending = TRUE`)
- **Counterexamples**: `spec/output/incr/MC-1-U2-counterexample.out` (9 steps from the seed),
  `spec/output/incr/MC-1-U3-counterexample.out` (22 steps from the seed, BFS-minimal)
- **Seed reachability**: the seed is State 17 of the full-MCNext witness `spec/output/incr/canary-seed.log`
  (16 MCNext steps from `MCInit`); the focused relation is a restriction of `MCNext`, so every step is a
  full-reference behaviour.
- **Full-reference admission**: `Update-seed-full-U1U3.cfg` (complete `MCNext` from the seed, MaxDrop=1) reaches the
  same U3 violation in 23 steps (`spec/output/incr/MC-1-U3-fullMCNext-counterexample.out`).

### Counterexample (U3), from the seed (s1 durably logged uncommitted t1 in epoch 1; all LOOKING)
1. `CastVote(s2,s1)`, `CastVote(s3,s2)`, `WinElection(s1)` — s1 leads epoch 2 (its log is longest).
2. `FollowLeader(s2,s1)`, `AcceptEpoch(s2)`, `FinishDiscovery(s1)`, `EnterSyncPhase(s2,s1)`.
3. `SelectSync(s2,s1,"DIFF")` — t1 buffered in s2's `packetsNotCommitted` (`syncPending`).
4. `LearnerNewLeader(s2)` — currentEpoch(s2)=2 persisted; t1 handed to `logRequest` (queued, **not durable**).
5. `LearnerAckNewLeader(s2)` — NEWLEADER ACK counted by s1 (U2 is already violated here).
6. `LeaderBroadcast(s1)` — quorum {s1,s2}; s1 serves its initial history: t1 committed/served in epoch 2.
7. `Crash(s2)` before SyncThread's append/fsync — t1 lost at s2; `Restart(s2)` with currentEpoch 2.
8. `WinElection(s2)` for epoch 3 (s3 votes for s2's higher currentEpoch), `FollowLeader(s3,s2)`, `AcceptEpoch(s3)`,
   `FinishDiscovery(s2)` (s3 is not ahead of s2), `EnterSyncPhase(s3,s2)`, `SelectSync(s3,s2,"DIFF")`,
   `LearnerNewLeader(s3)`, `LearnerAckNewLeader(s3)`.
9. `LeaderBroadcast(s2)` — s2 serves epoch 3 without t1, which s1 served in epoch 2: **U3 violated**.
   If s1 later rejoins s2 after the epoch-3 quorum formed, `waitForEpochAck` no longer checks it and the DIFF/TRUNC
   decision discards t1 there too.

(The BFS path casts s3's vote for s2 before epoch 2; the same vote is admitted after `Restart(s2)`, since s2's
currentEpoch 2 exceeds s3's.) The first campaign round found a variant through a discovery quorum that the real
`Leader.waitForEpochAck` rejects ("Follower is ahead of the leader"); that guard was added to `FinishDiscovery`
(Case B repair, changelog) and every campaign was re-run; the logs of the first round are kept as
`spec/output/incr/*-r1-pre-discovery-guard.log`.

Old-behaviour control (`Update-seed-oldcontrol-U3.cfg`, `MC-1-oldcontrol-U3-counterexample.out`): 21 steps and
**no crash** — s2 ACKs NEWLEADER, abandons the sync before UPTODATE (`BeginElection`), and the buffered t1 is simply
dropped. The update removed that crash-free path (hand-off before the ACK), but the crash-in-window path remains.

### Root cause
`Learner.syncWithLeader` NEWLEADER case (updated `Learner.java:743-760`): `self.setCurrentEpoch(newEpoch)`,
then `fzk.logRequest(...)` for every buffered proposal, then `writePacket(ACK newLeaderZxid, true)`.
`FollowerZooKeeperServer.logRequest` (`FollowerZooKeeperServer.java:82-89`) only enqueues to
`SyncRequestProcessor`; append (`SyncRequestProcessor.java:181`) and fsync (`flush`, `:227-249`) happen later on
SyncThread, and nothing waits for them before the ACK. The leader counts the ACK
(`Leader.waitForNewLeaderAck`, `Leader.java:1547-1575`) and serves the tree rebuilt from its whole log
(`Leader.java:593,688`). The update moved the hand-off before the ACK (its stated intent, `Learner.java:748`:
"make sure sync the uncommitted logs before commit them (ACK NEWLEADER)") but did not make the ACK wait for
durability, so the window is narrowed, not closed. The old revision has the same defect with a wider window
(hand-off only after UPTODATE): old-behaviour control `Update-seed-oldcontrol-U3.cfg` / repro old control.

### Affected code
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:743-760`
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:82-89`
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:181-249`
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:1547-1575, 663-688`

### Implementation evidence
- Fresh trace `traces/fresh/diff-sync-consistency.ndjson`: s0 `NewLeaderAckSent` (event 82) and the leader's
  BROADCAST (event 84) precede s0's `TxnDurable` of the handed-off txn (event 94); the actual
  `NewLeaderAckDurable` operator is violated at replay state 83 (`spec/evidence/trace-props/`).
- Reproduction (`harness/repro/test_bug1_newleader_ack_durability.sh`): REPRODUCED on the updated tree, same
  failure on the old tree, passes on a hypothetical flush-before-ACK control (`spec/confirmation-MC-1.md`).

## Not Reproduced / no violation within the explored bound

| Scenario | Config | Result |
|---|---|---|
| Update hand-off before ACK (U1) | Update-seed-focused-U1.cfg, Update-full-U1U3.cfg | no violation within bound; old-behaviour control violates it (expected) |
| Hypothetical flush-before-ACK | Update-seed-fixedcontrol.cfg | no U2/U3 violation within bound (control, not implementation) |
| Prior safety (TypeOK, ElectionSafety, OneActiveLeaderPerEpoch, CommittedHistoriesPrefix, ApplyRequiresCommitCertificate, PipelinePrefix, EpochHistoryConsistency, SyncCompletionJustified, HistoryPositionsMonotonicExceptRecovery) | MC.cfg | see changelog Round U - Model Checking |

Exact state counts, depths and queue sizes per run: `spec/output/incr/command-results.ndjson` and
`spec/model-checking-summary.md`.
