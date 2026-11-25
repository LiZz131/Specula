# Exact-old code analysis report

## Method and isolation

Analysis was restricted to `/work/source`, `/work/scope.md`, and
`/work/input-manifest.json`. The code-analysis archaeology/history/issue-search
phase was intentionally replaced by structural and deep code analysis. No
internet behavioral research, upstream Git history, issues, pull requests,
release notes, papers, benchmark labels, or later/fixed tree were inspected.
The source tree remained unmodified. The neutral baseline commit is
`774296b074905daf3924854264ec54c27842aa9f`.

## Architecture and concurrency

ZooKeeper's participant loop moves among LOOKING, FOLLOWING, and LEADING.
FastLeaderElection uses independent network sender/receiver workers and a main
election loop. After election, each follower has a Learner socket loop, a
SyncRequestProcessor thread, and a CommitProcessor thread; the leader additionally
has LearnerHandler sender/receiver activity and its own proposal/commit pipeline.
These threads make disk append, disk force, ACK delivery, commit notification,
and state-machine application independently schedulable.

The implementation's observable protocol phases are election, discovery,
synchronization, and broadcast. `QuorumPeer.setZabState` publishes these phases;
accepted and current epochs are maintained in separate atomically written files.

## Election and epoch findings

`FastLeaderElection.totalOrderPredicate` orders voting candidates first by peer
epoch, then zxid, then server id. A looking peer changes role only after the vote
tracker has all required quorums and the finalize wait finds no better queued
vote. A newly leading peer still cannot broadcast: `Leader.lead` first obtains a
new accepted epoch quorum, then rejects epoch acknowledgments whose history is
newer than the leader summary, and finally waits for a NEWLEADER quorum.

Epoch persistence has a clear crash boundary: `QuorumPeer.setAcceptedEpoch` and
`setCurrentEpoch` write the file before assigning the in-memory field. Learners
persist a greater accepted epoch before ACKEPOCH. They persist current epoch on
NEWLEADER (or legacy UPTODATE) before starting their server pipeline.

Model consequence: election decision, accepted epoch, current epoch, and public
broadcast are separate actions. A single `BecomeLeader` action would erase real
failure/interleaving states.

## Synchronization findings

`LearnerHandler.syncFollower` executes while holding the database committed-log
read lock and chooses:

- DIFF when the learner can extend from retained history;
- TRUNC when the learner must discard an uncommitted suffix without crossing an
  epoch boundary;
- SNAP when retained logs cannot bridge the history gap.

The handler queues the sync directive and needed proposal/commit pairs before
calling `startForwarding`. The learner independently consumes the directive.
SNAP clears and deserializes the data tree; TRUNC closes storage, truncates, and
reloads; DIFF retains the base and logs the suffix. Proposals arriving around
NEWLEADER are buffered and later written/committed after startup.

Model consequence: sync selection and completion must be guarded, and only
TRUNC/SNAP/crash recovery may authorize a decreasing modeled position.

## Transaction pipeline findings

On the leader, `ProposalRequestProcessor` sends the proposal into leader state
before queuing the request for SyncRequestProcessor. SyncRequestProcessor calls
`ZKDatabase.append`, accumulates the request in `toFlush`, calls database commit
(ultimately `FileChannel.force(false)` when forceSync is enabled), and only then
invokes AckRequestProcessor. Leader `tryToCommit` requires the proposal to be the
next outstanding zxid and to have quorum ACKs before broadcasting COMMIT and
submitting it to CommitProcessor.

On a follower, receipt of PROPOSAL appends a Request to `pendingTxns` and queues
it for asynchronous disk sync. Receipt of COMMIT independently removes the
matching queue head and submits it to CommitProcessor. The fresh trace confirms
the source permits this concrete order for a follower: ProposalQueued,
CommitDelivered, TxnAppended, TxnApplied, TxnDurable. This is not a violation of
the modeled property: the COMMIT packet is evidence of leader-side quorum
durability; the receiving follower's own fsync need not precede local apply.

Model consequence: `ApplyRequiresCommitCertificate` checks an ordered leader
commit certificate, not local durability of every applying replica.

## Persistence and recovery findings

Snapshots serialize the data tree and session state and are named with a last
processed zxid. Transaction append writes checksummed bytes through a buffered
stream; commit flushes and forces each active channel. Restore loads the latest
valid snapshot and fast-forwards transaction logs, applying each durable record.
Truncation closes the log, truncates at the requested zxid, recreates the database,
and reloads it.

Shutdown stops processors and can fast-forward the database from durable edits.
Because recovery replay does not itself reconstruct a separate quorum-commit
marker for every edit, the model keeps `recovered` history distinct from the
externally visible `applied`/`committed` history until re-election synchronization
justifies it.

## Failure assumptions

- Fail-stop peer crashes; restart reads intact snapshot/log/epoch files.
- Non-fsynced appended records may be lost on crash; forced records persist.
- Proposal, ACK, and commit messages may be delayed or dropped, not corrupted or
  forged. A delivered COMMIT represents a leader quorum decision.
- Fixed participant membership and majority quorums; no Byzantine behavior.
- SNAP/TRUNC/DIFF actions abstract file bytes but preserve history effects.

## Validation evidence

Four source tests passed under outer timeouts and produced nonempty traces:

| Scenario | Events | Evidence |
|---|---:|---|
| follower SNAP + mutation | 16 | `traces/follower-snap.ndjson` |
| follower DIFF | 15 | `traces/follower-diff.ndjson` |
| election/startup/client mutation/shutdown | 71 | `traces/quorum-startup-mutation-shutdown.ndjson` |
| leader abandonment/restart/recovery | 265 | `traces/leader-abandon-restart-recovery.ndjson` |

Trace TLC completely consumed all five retained files: 15, 16, 16, 265, and 71
events, each producing exactly one more trace state than event count and leaving
zero states queued. After those trace-first runs, canonical base BFS exhausted
6,354,157 distinct states and canonical MC BFS exhausted 21,701,056 distinct
states, both at the explicit level-23 bound with no violation and zero queued
states. Older broader timeout/open-frontier logs remain preserved only as
limited evidence. Negative-invariant hunts reached election, sync, committed
application, and crash/restart.

## Limitations and disposition

The evidence remains finite-bound coverage, not an unbounded proof: TLC constants
bound server count, epochs, transactions, crashes, message loss, and snapshots,
and the canonical state constraint bounds TLC at level 23. All retained traces
are now formally replayed. JDK 21 was the available runtime, outside the
manifest's preferred JDK 8 / allowed JDK 11, although the exact-old build/tests
succeeded. No implementation bug is claimed and no property was weakened to
obtain green output.

---

# V1 incremental update analysis (source revision `update`)

## Inputs and identity

- Old (exact V0) source: `/work/old-source` (changed files) and the V0 suite in
  `/work/previous/.specula-output` (immutable). New source: `/work/new-source`
  and the complete tree `artifact/` (neutral commits `baseline` → `update`,
  `git diff baseline update`). No history, issue tracker, internet, or fixed
  revision was consulted; the only intent statements used are source comments
  and the test added by the update.
- Changed files: `ZooKeeperServer.java`, `quorum/Learner.java`, and the new test
  `quorum/DIFFSyncConsistencyTest.java`.

## What the update changes (both revisions read in full)

1. `ZooKeeperServer.startup()` is split into `startupWithServerState(state)`;
   `startupWithoutServing()` starts every request processor but leaves the
   server in `State.INITIAL`; `startServing()` later sets `RUNNING`
   (`ZooKeeperServer.java:669-680`).
2. `Learner.syncWithLeader` Zab-1.0 NEWLEADER branch (`Learner.java:726-761`)
   now, after `setCurrentEpoch(newEpoch)`: sets the socket timeout, clears the
   sync mode, calls `zk.startupWithoutServing()`, hands every
   `packetsNotCommitted` entry to `FollowerZooKeeperServer.logRequest`
   (enqueue on `pendingTxns` + `SyncRequestProcessor.processRequest`), clears the
   buffer, and only then writes the NEWLEADER ACK. After UPTODATE the learner
   calls `zk.startServing()` instead of `zk.startup()` (`Learner.java:767`).
   Old revision: the same packets were logged only after UPTODATE
   (`old Learner.java:753-787`), so the NEWLEADER ACK was sent with the DIFF
   proposals neither queued nor persisted.
3. New test `DIFFSyncConsistencyTest` states the intended guarantee (followers
   that ACK NEWLEADER and then fail must not lose the leader-visible
   transaction; "Data inconsistency detected!").

## Chapter 1 decision: MODEL_CHANGE_REQUIRED

Projection onto the V0 vocabulary is not equal for the changed branch:
the NEWLEADER step now changes `queued/proposed` (logRequest) and `syncMode`
before the ACK, starts processors that can append/fsync/ACK concurrently with
the ACK write, and leaves the server in a non-serving state whose shutdown is a
no-op (`canShutdown()` false for `INITIAL`, `ZooKeeperServer.java:784-807`,
`LearnerZooKeeperServer.java:155-172`). V0 could not express any of these:
its `CompleteSync` installed the leader's *durable* history atomically, and its
`LeaderBroadcast` waited for followers to be in BROADCAST rather than for
NEWLEADER ACKs. The update therefore changes modeled state, atomicity and an
enablement condition, and the V0 abstraction had to be repaired to represent
the changed mechanism.

## Source-driven model changes vs. repairs (see `spec/changelog.md`)

Source-driven (UPDATE-MAP): `FollowerProcessNewLeader` (log before ACK, sync
mode cleared, INITIAL state), `FollowerSendNewLeaderAck` (separate ACK write),
`FsyncOne` ACK shadowing, `LeaderProcessNewLeaderAck`, `FollowerProcessUpToDate`
(startServing → RUNNING), `BeginElection` INITIAL branch (skipped shutdown,
leaked SyncRequestProcessor).

Repairs of V0 abstractions that the update depends on (REPAIR): NEWLEADER-ACK
quorum gating of `LeaderBroadcast` (Leader.java:663-712), UPTODATE only after
leader establishment (LearnerHandler.java:623-648), sync directive effects at
`SelectSync` (truncate/deserialize) and durability at the NEWLEADER branch,
in-memory DB history (`recovered`) as the vote/`loadData` source
(QuorumPeer.java:1257-1262, ZooKeeperServer.java:480-503), FLE zxid ordering,
RUNNING-exit fast-forward/drain, `ReceiveProposal` FIFO/forwarding guard
(Leader.java:1294-1325), broadcast-phase-only `ReceiveCommit`. Dead V0 actions
`QueueLearnerProposal`/`ObserveCommit` (not in V0 `Next`) were removed.

## Update Scenarios (derived from the diff)

- **U1 – NEWLEADER ACK before durability.** `logRequest` only enqueues; append
  and fsync run later on `SyncThread`. The ACK can therefore be counted by
  `Leader.waitForNewLeaderAck`, letting the leader establish and serve its
  initial history while the learner has not persisted it. A learner process
  crash (the appended bytes sit in `FileTxnLog`'s buffered stream until
  `commit()`) loses the DIFF txns although `currentEpoch` is already the new
  epoch, which outranks a learner that does hold them in FLE.
  Producer→affected→consumer: `SelectSync` (DIFF) → NEWLEADER branch →
  `LeaderBroadcast`/`FsyncOne`/`Crash`/`CastVote`/`WinElection`.
- **U2 – Crash between `setCurrentEpoch` and persistence** (same window, the
  epoch file is written before any DIFF txn is durable).
- **U3 – Txn ACK before the NEWLEADER ACK.** Processors start before the ACK
  write, so `SendAckRequestProcessor` can put a txn ACK first on the stream;
  `LearnerHandler` treats the first ACK as the NEWLEADER ACK and
  `waitForNewLeaderAck` rejects its zxid; the real NEWLEADER ACK is later
  ignored by `processAck`. Consequence: the learner is not counted (availability).
- **U4 – Failure between NEWLEADER ACK and UPTODATE leaves INITIAL state.**
  `Learner.shutdown → zk.shutdown()` returns early, so no fast-forward of the
  in-memory DB and no processor shutdown; the leaked `SyncThread` later writes
  the logged txns. The peer then votes and (if elected) leads with an in-memory
  history that omits durable, NEWLEADER-acknowledged txns.

## Trace evidence on the new implementation (fresh traces, see validation)

- `follower-diff`, `follower-diff-bulk-r1..r3`: the NEWLEADER ACK is written
  with 1 resp. 7 txns queued and `fsyncedZxidAtAck = 0`; the first fsync of a
  DIFF txn occurs only after UPTODATE.
- `diff-sync-uptodate-failure` (the update's own test): s0 ACKs epoch-2
  NEWLEADER with (1,2) queued but only (1,1) fsynced; leader s2 reaches the
  NEWLEADER quorum and enters BROADCAST while (1,2) is durable only on s2; s0
  then fails at UPTODATE, `ShutdownSkipped(INITIAL)` is observed, s0 goes
  LOOKING reporting in-memory zxid (1,1), and the leaked `SyncThread:0`
  fsyncs (1,2) and sends an ACK afterwards. The test still passes because it
  restarts every server from disk.
- No run showed U3 (the NEWLEADER ACK was first in all 8 fresh traces).

## V1 validation (trace) results

- Harness: V0 patch rebased (one hunk moved: `BroadcastReady` after
  `zk.startServing()`), V1 probes added; JDK 11 build; `harness/run.sh`.
- Conformance suite (13 fresh new-version traces, all pass TLC replay with
  `TraceMatched`, `records + 1` states each): the 4 rebased V0 scenarios
  (follower-snap/diff, quorum, leader-abandon), the update's
  `DIFFSyncConsistencyTest`, 3 × `SpeculaNewLeaderAckOrderTest`, 3 ×
  `SpeculaU4ReproTest`, 2 × `SpeculaDiffSyncControlTest`. The 3
  `SpeculaU1ReproTest` traces contain an injected loss of SyncRequestProcessor
  input plus an unprobed process restart and are kept as reproduction evidence
  only (`traces/fault-injected-repro/`).
- Trace interpretation repairs (inherited V0 checks, not weakened): role/phase/
  `FollowerRegistered`/`SyncModeChanged`/`SyncSelected`/`BroadcastReady` zxids are
  in-memory DataTree positions; `ElectionWon` carries the elected leader's zxid;
  an observed LEADING peer becomes the protocol leader when it persists its new
  accepted epoch (V1 `WinElection` is atomic over both); at most one protocol
  leader per epoch (was: one leader overall).
- Negative checks: 5 mutated traces are rejected exactly at the mutated event.
- Code observation of update properties (TLC on replayed states,
  `TraceUpdateEvidence.tla`): P1 violated on follower-diff, bulk-r1..r3 and
  diff-sync (NEWLEADER ACK with queued but not durable txns); P2 violated on
  diff-sync (leader certifies (1,2) durable only on itself); P5 violated on
  diff-sync and the U4 reproductions (LOOKING peer with log ahead of in-memory
  DB); P4 never violated.

## V1 model-checking results (final model; budget-limited)

- Standard `MC.cfg`: `PipelinePrefix` violated at depth 23 through the U4 path
  (MC-2). With the analysed class filtered (`MC-filtered.cfg`), BFS and
  simulation continue (see `spec/output/incremental/campaign-summary.md`).
- Update properties over full `MCNext` and over the concrete focused spec: P1,
  P4, P5 violated (late-joiner and establishment paths); P2 violated by
  simulation on full `MCNext` (55 states) and by the 2-server hunt; P3 violated by
  `HuntU1` (no-crash U4 path, 40 states; crash U1 path, 42 states).
- Discharge of omitted context against `EnvUpdate`: no violation within budget.
- Findings: MC-1 (U1/U2), MC-2 (U4), MC-3 (U3); see `spec/bug-report.md`.

## V1 reproduction (bounded, real implementation)

| Test | Revision | Runs | Outcome |
|---|---|---|---|
| `SpeculaU4ReproTest` (no restart after UPTODATE failure) | new | 3 | node served by old leader missing on new leader (3/3) |
| same | old | 1 | missing (1/1) |
| `SpeculaU1ReproTest` (stalled disk until restart) | new | 3 | missing (3/3) |
| same | old | 1 | missing (1/1) |
| `SpeculaDiffSyncControlTest` (update scenario, non-vacuous leader wait, no fault) | new | 2 | present (2/2) |
| same | old | 2 | missing (2/2) |
| `DIFFSyncConsistencyTest` (as shipped) | new / old | 1 / 1 | pass / pass — its `findLeader()` can return -1 right after restart, which skips the assertion |
| `SpeculaU3ReproTest` (learner pauses 1.5 s before its epoch ACK) | new | 1 | first ACK = txn (1,2) for both learners, rejected; no leader for 100 s (epochs 2-4) |
| same | old | 1 | leader established, 0 rejections |
| `SpeculaNewLeaderAckOrderTest` (no injection; 7/1500/3000 txns) | new | 9 | NEWLEADER ACK first in every run |

Attribution: the update fixes the restart-after-flush case of the original
inconsistency but leaves (a) the window where the NEWLEADER ACK precedes
durability (MC-1) and (b) the no-restart path after an UPTODATE failure (MC-2),
and it introduces leaked processors/log-vs-memory divergence for (b) and the ACK
ordering hazard (MC-3, reproduced only with an injected learner-thread pause).
