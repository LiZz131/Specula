# Exact-old ZooKeeper Zab V0 Analysis Report

## Input discipline and coverage

The analysis used only `/work/source`, `/work/work-source`, `/work/scope.md`, `/work/input-manifest.json`, `/work/lib`, `/work/tools`, and the six required workflow skills. No network research, upstream history, tags, remotes, papers, issue trackers, later source, other case outputs, Gold data, or remembered defect labels were used. The pristine tree and writable tree began at neutral commit `6250c9811a44ed94c825bb5a7cb80fd7b4b883a3`; the pristine tree remained unmodified.

The twelve priority files were read in full (13,771 LOC). Parallel deep reads also covered the directly necessary election, persistence, request-processor, atomic-file, snapshot, and test helpers. The repository has one neutral synthetic commit, so bug archaeology was intentionally inapplicable: significant historical commits analyzed 0; external issues/PRs collected/read/confirmed/excluded 0/0/0/0.

## Category and architecture

This is Category A: a crash-fault, message-passing replicated state machine. `QuorumPeer` keeps role (`LOOKING`, `FOLLOWING`, `LEADING`, `OBSERVING`) separate from Zab phase (`ELECTION`, `DISCOVERY`, `SYNCHRONIZATION`, `BROADCAST`) and sync mode (`NONE`, `DIFF`, `SNAP`, `TRUNC`) (`QuorumPeer.java:479-505,844-878`).

The peer main thread dispatches to election, follower, leader, or observer loops (`QuorumPeer.java:1344-1497`). Important independent schedulers are:

- election sender/receiver workers and the `lookForLeader` consumer (`FastLeaderElection.java:203-211,220-552,957-1103`);
- one connection handler plus a dedicated ordered sender for each learner (`LearnerHandler.java:325-375,457-753`);
- a per-server sync processor separating queue, append, flush, and callback (`SyncRequestProcessor.java:72-85,155-250`);
- a commit processor with worker scheduling for reads and serialized writes (`CommitProcessor.java:197-420,467-478`);
- a snapshot thread independent of later transaction application (`SyncRequestProcessor.java:180-201`).

These are modeled as separate transitions wherever their ordering can affect epochs, history, durability, commitment, or serving state.

## Election and epoch transitions

`FastLeaderElection` represents votes with leader, zxid, election epoch, peer epoch, and state. Candidate preference is higher peer epoch, then zxid, then server id (`FastLeaderElection.java:722-747`; `Vote.java:70-104`). Quorum tracking includes the current verifier and a newer last-seen verifier, if present (`FastLeaderElection.java:759-777`). An already established leader is accepted only with a quorum reporting the same vote plus direct evidence that the named leader reports LEADING (`FastLeaderElection.java:791-813,1054-1088`).

After election, leader discovery is a durable stair-step (`Leader.java:590-688,1391-1581`):

1. restore database and construct `(currentEpoch,lastProcessedZxid)`;
2. collect accepted epochs and propose their maximum plus one;
3. persist leader accepted epoch when a quorum including self has reported;
4. reject a follower summary newer than the leader and collect acceptable state summaries;
5. persist leader current epoch after the epoch-ack quorum;
6. synchronize learners and collect exact-zxid NEWLEADER ACKs;
7. start the ZooKeeper server and enter BROADCAST.

The learner sends `(acceptedEpoch,0)` in FOLLOWERINFO, receives LEADERINFO, persists a strictly newer accepted epoch, and sends ACKEPOCH carrying its last logged zxid and old current epoch. Equal accepted epoch retries carry `-1` so they do not count twice (`Learner.java:483-526`). At NEWLEADER, it persists current epoch before ACK (`Learner.java:726-760`). Accepted/current epochs are distinct atomic files and distinct calls (`QuorumPeer.java:2140-2173`).

## Synchronization decision and cut

`LearnerHandler.syncFollower` holds the committed-log read lock across decision, history queue construction, and `Leader.startForwarding` (`LearnerHandler.java:787-923`). Its source cases are:

- exact last-processed match: empty DIFF;
- learner ahead of max committed, non-epoch-boundary zxid: TRUNC;
- learner within committed-log range: DIFF or same-epoch TRUNC as the iterator establishes the common point;
- older learner with usable on-disk log: disk-log plus committed-cache DIFF;
- any uncovered range or a gap between disk and cache: SNAP.

Every historical transaction queued by the leader is a PROPOSAL followed by COMMIT (`LearnerHandler.java:946-1036`). Epoch-boundary zxids are synthetic and receive special DIFF handling (`LearnerHandler.java:775-787,982-989`).

`Leader.startForwarding` runs under the leader monitor, queues committed entries still awaiting local apply, then outstanding proposals, then registers the handler for future traffic (`Leader.java:1289-1321`). Network transmission is later. During SNAP serialization, new proposals can therefore accumulate after the snapshot bytes and around NEWLEADER/UPTODATE queueing (`LearnerHandler.java:549-648`).

Learner behavior preserves more cuts (`Learner.java:553-785`):

- SNAP replaces the in-memory database and is durably snapshotted at NEWLEADER;
- TRUNC clears/retracts/reloads history;
- DIFF keeps catch-up proposal/commit queues for later persistence;
- current epoch is persisted before NEWLEADER ACK;
- start-serving occurs at UPTODATE before residual catch-up queues have necessarily drained;
- Follower Zab phase changes to BROADCAST only after `syncWithLeader` returns (`Follower.java:105-111`).

## Broadcast persistence and request processing

The minimum transaction states justified by source are prepared, proposal-sent, sync-queued, buffered-appended, flush-pending, durable, acknowledged, globally committed, local-commit-queued, and applied.

Leader order:

1. `ProposalRequestProcessor` forwards the local request to `CommitProcessor`, calls `Leader.propose`, then queues local sync (`ProposalRequestProcessor.java:68-90`).
2. `Leader.propose` updates `lastProposed`, inserts in `outstandingProposals`, and queues PROPOSAL to learners (`Leader.java:1215-1256`).
3. `SyncRequestProcessor` later appends and batch-commits; only after commit returns does its ACK processor run (`SyncRequestProcessor.java:180-250`).
4. `Leader.processAck` records an ACK and `tryToCommit` requires every configured quorum and predecessor removal (`Leader.java:890-962,974-1041`).
5. Commit removes the outstanding proposal, records it to-be-applied, advances `lastCommitted`, sends COMMIT/INFORM, and queues local commit processing (`Leader.java:918-960,1132-1184`).
6. `FinalRequestProcessor.applyRequest` later calls `ZooKeeperServer.processTxn` (`FinalRequestProcessor.java:111-160`).

Follower order:

1. Receive PROPOSAL, put it in `pendingTxns`, and independently queue its sync (`Follower.java:160-203`; `FollowerZooKeeperServer.java:80-89`).
2. Append/flush then send ACK (`SyncRequestProcessor.java:180-250`; `SendAckRequestProcessor.java:40-63`).
3. Receive COMMIT, require matching pending head, remove it, and queue commit processing (`FollowerZooKeeperServer.java:91-110`).
4. Apply later through `CommitProcessor` and `FinalRequestProcessor`.

The source does not require a slow applying follower's own WAL to have flushed before COMMIT reaches its independent socket/commit pipeline. The correct modeled durability condition is global: a commit has a quorum witness, and every normal ACK in that witness followed that sender's completed log commit. `forceSync=yes` is the harness/default assumption for interpreting that boundary as power-loss durability (`FileTxnLog.java:371-405`).

## Snapshot and recovery

Normal snapshots are fuzzy. The filename zxid is sampled before serialization (`FileTxnSnapLog.java:464-472`), and the traversal can interleave with later applies. The source prevents the filename frontier from being ahead of the transaction that produced the sampled tree frontier, while replay tolerates effects present both in a snapshot and later WAL (`DataTree.java:1096-1128`; `FileTxnSnapLog.java:317-445`). Invalid partial snapshots are skipped in favor of a valid older one (`FileSnap.java:68-119`).

Restart restores a snapshot then replays every complete later WAL record (`FileTxnSnapLog.java:243-368`). The playback listener adds each replayed record to the in-memory field named `committedLog` (`ZKDatabase.java:272-341`), but this is a synchronization cache, not evidence that the record had a pre-crash quorum certificate. The model therefore separates `recoveryVisible` accepted history from client-visible `applied` committed history.

TRUNC is an explicit, source-authorized regression: clear database, close store, cut the durable log, reopen, then restore (`ZKDatabase.java:599-610`; `FileTxnSnapLog.java:502-523`). Other normal durable/commit/apply changes are monotone.

Graceful shutdown and crash differ. Graceful sync shutdown enqueues a death marker at the queue tail, joins the thread, and flushes pending work (`SyncRequestProcessor.java:254-270`); abrupt crash loses volatile queues without this drain. Both retain already published epochs, valid snapshots, and the complete durable WAL prefix.

## Abstractions selected

- A fixed set of three voting participants and strict majority intersection. Dynamic reconfiguration and observers are deferred because the fresh baseline scenarios do not mutate membership.
- Transaction identities are dense ordinals assigned from real zxids by the harness. Ordering/content equality is preserved without numeric-width or serialization detail.
- `durable` is completion of `FileTxnLog.commit` under `forceSync=yes`.
- `applied` is client-visible broadcast state. Non-serving recovery replay is `recoveryVisible` so accepted-but-uncommitted WAL entries do not become false global commits in the model.
- Message bytes/TCP frames are abstracted to source-level events and FIFO stage boundaries.
- SNAP is represented with begin and finish images; byte-level per-node fuzziness is documented but not expanded into serialization steps in V0.

## Harness plan and evidence

The harness adds dormant probes enabled only by `-Dspecula.trace.file`. It maps real server ids to `s0..s2` and real modeled mutation zxids to dense transaction ids. Each line has a real `System.nanoTime()` timestamp and `tag="trace"`.

The source-derived scenario uses the real three-server test framework to perform:

1. ordinary startup/election/synchronization;
2. a client create mutation;
3. graceful shutdown of all peers;
4. full restart, database recovery, and re-election;
5. shutdown of one follower;
6. a client setData mutation on the live quorum;
7. restart/catch-up of the lagging follower;
8. final orderly shutdown.

The trace consumes role/phase/epoch/sync state plus transaction queue, flush, ACK, commit, and apply events. Instrumentation points execute in the real old code paths; no simulator or hand-authored trace is used.

## Analysis disposition

No known incident was investigated and no historical defect conclusion is reported. The four model-checkable items in the modeling brief are neutral questions about exact-old behaviors. Any TLC violation must still be classified against exact-old implementation code as invariant mismatch, modeling gap, or implementation finding before appearing in `bug-report.md`.

---

# Incremental update analysis (case-010, source `baseline` -> `update`)

## Inputs and identity

- Old source: `/work/old-source/` (changed-file snapshot) and artifact commit `baseline` (`f8533cd`).
- New source: `/work/new-source/` and artifact commit `update` (`b16ba7105238d46b0d51e3cc5d92ce9fe16de834`, recorded in `spec/output/new-source-head.txt`).
- Prior suite: `/work/previous/.specula-output/` (immutable). Its trace/model validation logs report no unresolved errors; its MC results are `LIMITED_COVERAGE` (frontier not exhausted) and are carried as such.
- Changed files: `ZooKeeperServer.java` (+3), `quorum/Learner.java` (+3/-1), `QuorumPeerMainTest.java` (+128 test `testDiffSyncAfterSnap` and test hooks). Only the neutral two-commit diff, the two snapshots, and the prior suite were used.

## Changed behavior (new vs old), read in context

1. `Learner.shutdown()` (`Learner.java:850-866`) now calls `zk.shutdown(self.getSyncMode().equals(SNAP))` instead of `zk.shutdown()`.
2. `ZooKeeperServer.shutdown(boolean)` (`ZooKeeperServer.java:803-810`) now clears `zkDb` when the server was never started (`!canShutdown()`) and `fullyShutDown` is true.
3. New test `QuorumPeerMainTest.testDiffSyncAfterSnap` (new `QuorumPeerMainTest.java:1618-1743`) injects an IOException right after a follower reads NEWLEADER during a forced SNAP sync, then checks that after a DIFF re-sync and a restart every created node still exists.

Callers/callees/consumers read in both revisions: `QuorumPeer.run` FOLLOWING case (`QuorumPeer.java:1468-1480`) and `QuorumPeer.shutdown` (`QuorumPeer.java:1538-1570`) call `follower.shutdown()`; `Follower.followLeader` (`Follower.java:72-160`); `Learner.syncWithLeader` (`Learner.java:546-812`); `ZKDatabase.clear/loadDataBase/fastForwardDataBase/truncateLog/deserializeSnapshot` (`ZKDatabase.java:171-188,284-304,599-622`); `QuorumPeer.getLastLoggedZxid` (`QuorumPeer.java:1257-1262`) which reloads an uninitialized database; `ZooKeeperServer.loadData` (`ZooKeeperServer.java:480-512`); `LearnerZooKeeperServer.shutdown()` (`LearnerZooKeeperServer.java:154-173`); `ObserverZooKeeperServer.shutdown()` (`ObserverZooKeeperServer.java:131-140`); `SyncRequestProcessor.run/flush/shutdown` (`SyncRequestProcessor.java:156-279`); `LearnerHandler.syncFollower/queueCommittedProposals` (`LearnerHandler.java:775-1036`); `Leader.startForwarding` (`Leader.java:1289-1322`).

### Branch projection

`syncMode` is written only at `Learner.java:563,566,589` (DIFF/SNAP/TRUNC at sync start) and reset only at `Learner.java:750` (NEWLEADER). It is not reset on learner exit, election, or leadership; a fresh `QuorumPeer` starts with `NONE`. The `ZooKeeperServer` state is `INITIAL` until `startServing()` after UPTODATE (`Learner.java:767`, `ZooKeeperServer.java:669-680`); processors exist after `startupWithoutServing()` at NEWLEADER (`Learner.java:751`).

| Learner exit branch | Old behavior | New behavior | Projected model effect |
|---|---|---|---|
| A. `syncMode=SNAP`, server not running (failure after SNAP was read, before NEWLEADER processing) | `LearnerZooKeeperServer.shutdown()` returns early; the in-memory SNAP image (and any in-sync COMMITs applied directly at `Learner.java:656-665`) is retained though no snapshot was written (`Learner.java:739-741` not reached) | `ZooKeeperServer.shutdown(true)` clears `zkDb`; the next `getLastLoggedZxid()` reloads snapshot+WAL from disk | **Changed**: the in-memory baseline used for the next vote/FOLLOWERINFO becomes the recoverable on-disk history instead of an unpersisted image |
| B. `syncMode` DIFF/TRUNC/NONE, server not running (before UPTODATE) | early return, memory retained; processors (if NEWLEADER passed) are not shut down | `shutdown(false)`: early return, memory retained; processors not shut down | Unchanged |
| C. server RUNNING (after UPTODATE; `syncMode=NONE`) | `LearnerZooKeeperServer.shutdown()` -> `ZooKeeperServer.shutdown(false)` (fast-forward) **then `syncProcessor.shutdown()`**, which drains, flushes and joins the follower log thread before `Learner.shutdown` returns | `zk.shutdown(false)` dispatches directly to `ZooKeeperServer.shutdown(boolean)`, which `LearnerZooKeeperServer` does not override; the follower `SyncRequestProcessor` is **never shut down**. Its queued writes are appended later by a still-running thread that shares the peer's `zkDb`/txn log, and the thread leaks | **Changed**: the drain is no longer inside the learner-exit step; stale queued txns may reach the log after the next election/sync (after TRUNC, after reload, interleaved with the next lifecycle's log writes) |
| D. `QuorumPeer.shutdown()` of a follower | drains the follower queue (branch C) before `zkDb.close()` | no drain; queued writes are lost or written by the leaked thread | Prior model already admits loss of queued, un-ACKed writes at process shutdown (GracefulShutdown + restart); no new modeled state |

Branch C is a side effect of the call-site change (virtual dispatch of the new overload), not of the new `clear()` guard. The same bypass applies to `ObserverZooKeeperServer.shutdown()`; observers remain outside the modeled scope.

### Sibling-path check (same mechanism)

`snapshotNeeded` is true for both SNAP and TRUNC (`Learner.java:553-555`: "For SNAP and TRUNC the snapshot is needed to save that history"), so both modes apply in-sync COMMITs directly to memory (`Learner.java:612-614,656-665`) and persist them only via `takeSnapshot` at NEWLEADER. A TRUNC-mode learner that fails after an in-sync COMMIT and before NEWLEADER therefore carries an unpersisted in-memory image, exactly like the SNAP case, but the new guard tests only `SNAP`. The leader sends TRUNC followed by PROPOSAL/COMMIT for committed-but-not-yet-applied proposals (`LearnerHandler.java:848-857` then `Leader.startForwarding`, `Leader.java:1292-1302`). This is a pre-existing path that the update leaves unchanged; it is recorded as an update Scenario because the update is the mechanism's repair.

## Disposition

`MODEL_CHANGE_REQUIRED`. Branches A and C change modeled post-states (in-memory sync/vote baseline, and the atomicity of the follower log drain relative to the next lifecycle). The prior model cannot express either: SNAP/TRUNC reconciliation was one atomic `CompleteLearnerSync` step that made the image durable immediately, there was no per-follower learner exit, `syncMode` was reset at election, a follower could not re-join a leader already in BROADCAST, and `QueueForSync`/`FlushTxnLog` required a contiguous durable history (masking any log gap).

## Prior-model defects repaired because the update depends on them

1. Atomic SNAP/TRUNC reconciliation (`CompleteLearnerSync`) -> split into mode selection, snapshot load / log truncation, in-sync direct apply, sync snapshot at NEWLEADER, NEWLEADER ACK, and UPTODATE.
2. No learner exit -> new `LearnerShutdown`/`LearnerExit` and `ReloadDatabase` actions.
3. `syncMode` reset in `BeginElectionRound` -> removed (not in source).
4. Durable contiguity guards in `QueueForSync`/`FlushTxnLog` -> FIFO queue semantics; a recoverable history may now have gaps or stale entries, which the properties must judge.
5. MC could not let a follower sync with a leader already in BROADCAST, and persisted a follower's current epoch before sync data -> source order (`Learner.java:739-760`).
6. Sync mode was fully nondeterministic -> constrained by the leader decision (`LearnerHandler.java:841-932`) on the follower's advertised in-memory history.
7. Dense-id commit guard (`t = Len(globalCommitted)+1`) assumed no proposal is ever lost -> commit in the leader's outstanding order (`Leader.java:890-905`).

## Incremental results (final)

- **Update intent (UPD-1) holds within bounds**: with the new shutdown semantics the SNAP-interrupted re-join scenario is explored completely (144,904 states) without any violation; with the exact-old semantics the model and the real old revision both lose committed txns 1-10 on the re-joined follower (old trace recovered `[11]`; old test fails "node 0 should exist").
- **MC-1 (introduced by the update)**: `zk.shutdown(boolean)` bypasses `LearnerZooKeeperServer.shutdown()`, so the follower `SyncRequestProcessor` is never stopped or drained on learner exit. Deterministic thread leak in real code; in the model, txns queued at exit are written later by the leaked thread, so a re-synced follower's recoverable log can miss a committed txn or contain stale records after newer ones. The exact-old semantics are exhaustively clean for the committed-gap property in the same scenario.
- **MC-2 (pre-existing, not closed by the update)**: the TRUNC branch has the same unpersisted in-memory window as SNAP but is not covered by the new guard.
- **MC-3 (pre-existing)**: old shutdown fast-forwards before draining; re-sent records can follow newer ones in the follower log.
- Evidence for every property decision: `spec/invariant-evidence.json`; findings: `spec/bug-report.md`, `spec/findings.json`; campaign table: `spec/output/final-campaign-table.md`.
