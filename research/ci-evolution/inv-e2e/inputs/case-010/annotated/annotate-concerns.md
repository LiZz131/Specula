# Concerns about the model and contradicting evidence

These are observations only. The model was not changed; all model text in `out/spec-annotated/` matches `spec-original/` except for added `\*` comment lines. Line references to `base.tla`/`MC.tla` are to `spec-original/`. Source paths are relative to `source/zookeeper-server/src/main/java/org/apache/zookeeper/server/` unless stated otherwise.

Confidence labels: **confirmed** = reproduced with TLC on a scratch copy; **code-reading** = derived from reading the source at this revision, not executed; **model-reading** = derived from reading the model.

---

## C1. SnapshotPublishedValid can be violated in `MCNext` with MaxEpoch = 2 (confirmed)

A scratch run found a reachable violation of `SnapshotPublishedValid` under the MC-full constants (`Server = {s1,s2,s3}`, `MaxEpoch = 2`, `MaxTxn = 1`, `NEXT MCNext`). The run used `out/tmp/tlc/Scn2.tla`, which `EXTENDS MC` and adds only a pruning `CONSTRAINT` (it removes behaviours and adds none), so the trace is a real `MCNext` behaviour. Full trace: `out/tmp/scn2-counterexample.log` (56 states).

Outline:
1. s1 leads epoch 1. s2 syncs (DIFF) and enters broadcast. s3 enters SYNCHRONIZATION but never completes sync.
2. s1 proposes txn 1. s3 receives it, flushes it, and acks it. s1 commits with `commitWitness = {s1, s3}`. s2 runs `FollowerCommit` and `ApplyTxn` for txn 1, then publishes a snapshot `<<1>>`.
3. s1 crashes. A new round elects s3, because `durable[s3] = <<1>>` is not shorter than `durable[s2] = <<>>`. s3's `committed` is still `<<>>`.
4. s2 syncs with s3 using TRUNC. `CompleteLearnerSync` sets `committed[s2] := committed[s3] = <<>>` and `applied[s2] := <<>>`. Its `snapshotPublished[s2]` stays `<<1>>`, so `SnapshotPublishedValid` fails.

Final state: `globalCommitted = <<1>>`, `committed = (s1 <<1>>, s2 <<>>, s3 <<>>)`, `applied = <<>>` everywhere, `snapshotPublished[s2] = <<1>>`, `role[s3] = LEADING`.

Root-cause reading (model-reading):
- A new leader's `committed[l]` is never brought up to the history in its own log. No action adds already-committed or logged transactions to the new leader's `committed`.
- zookeeperInternals.md:249-250 says "any uncommitted proposals from a previous epoch seen by a new leader will be committed by that leader before it becomes active".
- In the code, `Leader.lead()` calls `zk.loadData()` (Leader.java:593), and the leader syncs followers from its database/committedLog (LearnerHandler.java:775ff).
- The same trace shows a committed transaction disappearing from a live follower (s2: `<<1>>` → `<<>>`). `MonotoneUnlessRecovery` does not flag this because of its sync-step exemption (C5).

Configs that can reach this:
- **Can:** MC-full.cfg (described in its own header as "limited/open-frontier evidence") and MC-wide.cfg both use `MCNext` with `MaxEpoch = 2`.
- **Cannot:** MC.cfg and MC-core-diagnostic.cfg (`MCCoreNext`: no crash or new round); MC-complete-candidate.cfg (`MaxEpoch = 1`); MC-recovery-complete.cfg (fixed witness leader and follower); MC-snapshot-complete.cfg (no crash).

A clean result from those configs therefore says nothing about this path.

## C2. A follower that has not finished sync can supply a quorum ack (confirmed in the same trace)

In the C1 trace, s3 is in SYNCHRONIZATION with `syncComplete[s3] = FALSE`, yet `FollowerPendingProposal`, `QueueForSync`, `FlushTxnLog` and `RecordProposalAck` let its ack count toward the commit quorum (states 28-35).

In the code (code-reading):
- `LearnerHandler.run` treats the first packet after NEWLEADER as the NEWLEADER ACK (LearnerHandler.java:612-623).
- It processes proposal ACKs only in the later loop (LearnerHandler.java:650-678).
- A syncing learner logs proposals only at NEWLEADER (Learner.java:752-758) or after UPTODATE (Learner.java:777-785).

So the model allows an ordering the code does not seem to allow.

## C3. Durability at NEWLEADER ACK is not checked by any property (code-reading + model-reading)

Learner.java:748 says "ZOOKEEPER-3911: make sure sync the uncommitted logs before commit them (ACK NEWLEADER)". Commit b978dfb9 says: "Make sure follower to persist all DIFF proposals before they ACK NEWLEADER."

In the model, `CompleteLearnerSync` adds the follower to `newLeaderAcks` without any condition on `durable[f]`. `NormalAckHasDurabilityEvidence` covers only proposal acks (`acks`), not `newLeaderAcks`. No invariant expresses the ZOOKEEPER-3911 intent.

Code-reading at this revision:
- `syncWithLeader` calls `fzk.logRequest(...)` (Learner.java:752-758).
- `logRequest` only enqueues to the SyncRequestProcessor (FollowerZooKeeperServer.java:88 → SyncRequestProcessor.java:276-277).
- The NEWLEADER ACK is then written at Learner.java:760.

I found nothing in `syncWithLeader` that waits for the flush before that ACK. Whether the flush can lag the ACK was not tested. A property such as "a follower in `newLeaderAcks[l]` has the synced prefix in `durable`" would test the stated intent.

## C4. ActiveLeaderUniqueness: the docs disagree, and the model may make it hold by construction (model-reading)

- Contradicting evidence: zookeeperInternals.md:257-259 says ZooKeeper does "not count on" a single coordinator and refers to "old leaders believing they are still active". zookeeperInternals.md:278 describes "two servers simultaneously think they are the leader". The formula counts local state (`running ∧ LEADING ∧ BROADCAST`), so in the real system it can be false for a while (until `Leader.lead` notices the quorum loss at Leader.java:760-766).
- In the model, `BeginElectionRound` is disabled while any running server is LEADING in BROADCAST (base.tla:185). In MC a broadcasting leader can only leave through `Crash` (at most one, `MCCrash`) or `GracefulShutdown`. A partitioned stale leader next to a newly elected one therefore cannot be produced, and the invariant may hold mostly because of this guard.
- In trace mode, `ObserveElectionResult`/`ObserveSetZabState` have no such guard, so the invariant is a real check there.

## C5. MonotoneUnlessRecovery: the exemption is broader than the documentation (model-reading, shown in C1)

`MonotoneStep` exempts the whole step whenever any follower's `syncComplete` flips to TRUE. That covers `committed` and `applied` as well as `durable`, on every server. zookeeperInternals.md:180-183 says only the uncommitted proposals `U` are discarded when a follower connects. The C1 trace shows the exemption hiding the loss of a committed and applied transaction at s2.

## C6. Several invariants are enforced by action guards (model-reading)

In MC these properties hold largely by construction. In trace mode, a violation in the code would show up as a trace mismatch (`TraceMatched` failing) rather than as an invariant violation, which makes the failure harder to interpret.
- `AcceptedEpochGECurrentEpoch`: `PersistCurrentEpoch` requires `e <= acceptedEpoch[s]` (base.tla:282). `RestartLoadDatabase` requires `ce <= ae` (base.tla:133). `FormEpochQuorum` requires `epochProposal[l] <= acceptedEpoch[l]` (base.tla:313). The code's `setCurrentEpoch` calls (Learner.java:721, :743; Leader.java:658) have no such check; they rely on the earlier `registerWithLeader`/`getEpochToPropose` ordering.
- `NormalAckHasDurabilityEvidence`: `RecordProposalAck` requires `source \in durabilityEvidence[t]` (base.tla:450). `durabilityEvidence[t]` is a history variable that is never cleared when a server's log is truncated or replaced (`CompleteLearnerSync` TRUNC/SNAP) or on `Crash`, so it can be stale relative to `durable[s]`.
- `SyncEntryJustified`: in MC, BROADCAST is entered only through `MCLeaderBroadcast`/`MCFollowerBroadcast`, whose guards are the invariant's right-hand side.
- `OrderedHistories`: append guards of the form `t = Len(...) + 1` force dense histories. The code only logs a warning on a zxid gap (Learner.java:627-632, Follower.java:171-176).

## C7. Restart does not rebuild applied state the way the code does (code-reading + model-reading)

`RestartLoadDatabase` leaves `committed` and `applied` unchanged (base.tla:148-151). In the code, a restart reloads the database:
- `ZKDatabase.loadDataBase` → `FileTxnSnapLog.restore` → `fastForwardFromEdits` (persistence/FileTxnSnapLog.java:317-344) replays every logged transaction after the snapshot, including proposals that were logged but never committed.
- After a restart, the code's in-memory state can therefore contain uncommitted transactions until the next TRUNC/SNAP. `ApplyHasCommitCertificate` would reject this if it were modelled, so the property is not exercised against the real post-restart state.

## C8. Applied without being locally durable (model-reading, seen in C1)

In the C1 trace, s2 commits and applies txn 1 while `durable[s2] = <<>>`. `FollowerCommit`/`ApplyTxn` do not require the transaction in the local `durable`. zookeeperAdmin.md:2618-2619 says "Before any update takes place, ZooKeeper ensures that the transaction that represents the update is written to non-volatile storage." No property relates `applied` to `durable`. I did not check whether the follower code enforces this per server.

## C9. Snapshots are fuzzy in the code but exact in the model (model-reading)

`BeginSnapshot` copies `applied[s]` exactly. zookeeperAdmin.md:2598-2607 says snapshots are fuzzy: they include "a subset of the updates ... that occurred while the snapshot was in process" and "may not correspond to any data tree that actually existed". The NEWLEADER-time snapshot taken during sync (Learner.java:739-741) is not modelled. This is a reasonable abstraction, but `SnapshotPublishedValid` checks the exact-prefix version only.

## C10. Follower "sync complete" is earlier in the model than in the code (model-reading)

`syncComplete[f]` becomes TRUE at `CompleteLearnerSync`, which is also the NEWLEADER ack. The code sets the follower's Zab state to BROADCAST only after `syncWithLeader` returns (Follower.java:109-110). That happens after UPTODATE and after the post-sync logging and commits (Learner.java:711-725, 765-785). The follower clause of `SyncEntryJustified` is therefore weaker than what the code does.

## C11. Documented guarantees with no property (model-reading)

- zookeeperInternals.md:117 and :119 together imply that every committed transaction is durable on a quorum. No invariant states this. It would directly cover the ZOOKEEPER-3911 data-loss scenario in DIFFSyncConsistencyTest.
- zookeeperInternals.md:249-250 says a new leader commits the previous epoch's proposals before it becomes active. No invariant states it; C1's final state has `role[s3] = LEADING` with `committed[s3] = <<>>` while `globalCommitted = <<1>>`. (s3 is not yet in BROADCAST in that state, so a check at BROADCAST entry would be the natural form.)

## C12. Config coverage (model-reading)

- MC.cfg and MC-core-diagnostic.cfg run `MCCoreNext == MCNext /\ UNCHANGED counters`, which excludes crash, restart, snapshot and new election rounds.
- MC-recovery-complete.cfg uses fixed witness servers, so a different server is never elected.
- MC-complete-candidate.cfg has `MaxEpoch = 1`.
- base.cfg/base-wide.cfg use `BaseNext` with one fixed leader and one fixed follower.
- New-leader recovery paths are therefore reachable only in MC-full.cfg and MC-wide.cfg (C1).
