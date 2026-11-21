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

## Incremental update analysis (case-010)

### Inputs and identity

- Old: `/work/old-source` (changed-file snapshot) and `/work/previous/.specula-output` (V0 suite, immutable).
- New: `/work/new-source` and `artifact/` at neutral commit `update` `b16ba7105238d46b0d51e3cc5d92ce9fe16de834` (parent `baseline` `f8533cd`). Exactly three files changed (`ZooKeeperServer.java`, `Learner.java`, `QuorumPeerMainTest.java`).
- No network research, history, issues or later revisions were used. Network was used only by Maven for ordinary build dependencies.
- Prior provenance gap: the V0 `harness/patches/instrumentation.patch` reproduces only the schema-v1 probe (common fields); the V0 `*-stateful.ndjson` schema-v2 traces were produced by a probe variant that is not preserved. V0 results are treated as provisional evidence for the old model only.

### Before/after behaviour of the changed path

| Exit point of a learner (`Learner.shutdown`) | zk state | Old (`shutdown(false)`) | New (`shutdown(syncMode==SNAP)`) |
|---|---|---|---|
| SNAP mode, after `deserializeSnapshot`, before NEWLEADER snapshot | INITIAL (not running) | early return; data tree = leader image (+ in-memory COMMITs), not on disk | `zkDb.clear()`; next `getLastLoggedZxid` reloads disk |
| SNAP mode, after NEWLEADER snapshot but before `setSyncMode(NONE)` | INITIAL | early return; image is on disk | clear + reload (same content) |
| TRUNC mode, before NEWLEADER, after in-memory COMMIT | INITIAL | early return; in-memory txn kept | **unchanged** (mode is TRUNC) |
| DIFF mode, any stage before UPTODATE | INITIAL | early return | unchanged |
| any mode after UPTODATE (`syncMode` reset to NONE at NEWLEADER) | RUNNING | drain sync processor, `fastForwardDataBase` | unchanged (fullyShutDown=false) |
| stale `syncMode==SNAP` from an earlier aborted SNAP, exit before the next first packet | INITIAL | early return | clear + reload of a disk-consistent database (CR-U1) |

Consumers of the changed state: `FastLeaderElection.getInitLastLoggedZxid` (`:867-875`), `Learner.registerWithLeader` (`:487,524`), `LearnerHandler.syncFollower` decision on `peerLastZxid` (`:775-932`), `Leader.lead` `zk.loadData` (`ZooKeeperServer.java:660-667`) when the peer becomes leader, and `QuorumPeer.loadDataBase` (`:1101-1150`).

### Reused abstraction defects repaired (needed for the update and its interactions)

1. No volatile/durable split for the data tree; the election compared `durable` directly (V0 `ElectionUpToDate`). Repaired with `memDb`/`memInit` and `LastLoggedHist`.
2. Learner sync was one atomic step and the follower persisted `currentEpoch` before entering SYNCHRONIZATION; the code persists it while handling NEWLEADER (`Learner.java:743`). Repaired by splitting the sync.
3. A follower could sync only while the leader was in SYNCHRONIZATION, so late joiners (the update test, V0's own restart-catch-up scenario) were unreachable in MC. Repaired (`LeaderEpochAgreed`, out-of-election join).
4. Dense txn prefixes made divergent histories and therefore TRUNC unrepresentable. Repaired with ordered histories with gaps.
5. `ActiveLeaderUniqueness` asserted one BROADCAST leader globally; the code permits a deposed leader to report BROADCAST until its next quorum check (`Leader.java:739-780`). Revised to the scope's per-epoch uniqueness.

Repairs are recorded separately from the source-delta disposition in `spec/changelog.md`.

### Outcome of the incremental run

- Validation: rebased harness (V0 patch + schema-v3 update-local probes) produced four fresh traces on the updated source; all replay completely against the final reference with real-object post-state checks (`spec/validation-handoff.md`, `traces/INVENTORY.md`).
- Model checking (bounded, `spec/output/verification-summary.md`): the updated SNAP branch behaves as intended within the explored bounds (the exact-old branch fails the same properties at depth 39/57 under the same schedule). Two findings remain on adjacent branches of the same mechanism:
  - **MC-1**: TRUNC sync also applies COMMITs in memory before the NEWLEADER snapshot, but the update clears the database only for SNAP; a TRUNC-window exit therefore keeps and reports a non-durable record, and an empty-DIFF resync later leaves a committed hole on disk. Reachable without crashes when a learner reports a record that the leader committed but has not yet applied.
  - **MC-2**: a DIFF learner that exits after NEWLEADER and before UPTODATE has logged records its data tree does not contain and reports the lower zxid; the next epoch can be built without such a record while it stays in that server's log.
- Both are pre-existing in the old revision; MC-1 is the sibling of the defect class the update repairs and is not fixed by it. Real-system reproduction was not part of this task.
