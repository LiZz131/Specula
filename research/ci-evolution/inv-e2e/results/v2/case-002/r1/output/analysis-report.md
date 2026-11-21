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

# Incremental update analysis (current run)

## U.1 Exact inputs

- Old: `/work/old-source` = artifact commit `baseline` 1414ebfb1d16fd81abc38550a96950d919ecf805
  (identical to the prior suite's analyzed tree for the changed files).
- New: `/work/new-source` = artifact commit `update` 2efbdfc3754df193bce05b9792297c813377cdaf.
- Changed: `ZooKeeperServer.java` (startup split into `startupWithoutServing()`
  -> state INITIAL and `startServing()` -> RUNNING), `quorum/Learner.java`
  (NEWLEADER branch), new test `DIFFSyncConsistencyTest.java`.
- Prior suite: `/work/previous/.specula-output` (no unresolved trace or MC errors;
  canonical BFS completed at depth 23; no findings).
- Category A retained (no change of concurrency/communication architecture).

## U.2 Behavior before and after (Learner.syncWithLeader)

| Step | exact-old | updated |
|---|---|---|
| NEWLEADER | snapshot if SNAP; `setCurrentEpoch`; ACK(NEWLEADER) | snapshot if SNAP; `setCurrentEpoch`; `setSyncMode(NONE)`; `zk.startupWithoutServing()` (request processors incl. `SyncRequestProcessor` start, server state INITIAL); every buffered `packetsNotCommitted` proposal -> `fzk.logRequest` (enqueue only) ; `packetsNotCommitted.clear()`; ACK(NEWLEADER) |
| UPTODATE | ACK; `setSyncMode(NONE)`; `zk.startup()` (processors start, RUNNING); log all buffered proposals; deliver buffered commits | ACK; `zk.startServing()` (RUNNING); log proposals buffered after NEWLEADER; deliver buffered commits |

Projection onto the prior model vocabulary: the post-state of the NEWLEADER ACK
changes (queued history of the learner, sync mode, running processors), the
atomicity boundary between "history handed to the log" and "ACK" changes, and
the enablement of `ClearSyncMode` changes. The prior model did not even
represent the ACK: its atomic `CompleteSync` made the leader's history DURABLE
at the learner immediately, and leader activation waited for learners to reach
BROADCAST. Both are implementation-backed defects of the prior abstraction that
the update directly depends on.

**Disposition: MODEL_CHANGE_REQUIRED** (projected post-state sets differ at the
NEWLEADER boundary; requirement-level property affected).

## U.3 Reference repairs and refinements (see spec/changelog.md)

1. `CompleteSync` split into `ReceiveSyncPayload` (stream buffered in
   `pendingSync` = packetsNotCommitted), `PersistCurrentEpoch`, `ClearSyncMode`
   (now ordered before the ACK), `AckNewLeader` (logRequest enqueue + ACK,
   counted by the leader in `nlAcks`), `EnterBroadcast` (UPTODATE).
2. `LeaderBroadcast` now activates on a quorum of NEWLEADER ACKs and commits the
   leader's loaded history (`Leader.waitForNewLeaderAck`, `startZkServer`).
3. Leaving a role (`BeginElection`): RUNNING -> processor drain/flush plus
   `fastForwardDataBase` (leader flushes before the fast-forward, learner after);
   NOT RUNNING (updated INITIAL window) -> `canShutdown()` is false, nothing is
   stopped or fast-forwarded and the started `SyncRequestProcessor` keeps running.
4. New in-memory history `memHist` (trace-driven): FLE votes, ACKEPOCH
   `lastLoggedZxid` and DIFF/TRUNC/SNAP selection use the in-memory database
   position, and a new leader serves `zk.loadData()`'s in-memory database.
5. Removed unfaithful prior actions `QueueLearnerProposal` (learner invents a
   txn) and `ObserveCommit` (learner certifies without a leader quorum);
   `FollowLeader` only from LOOKING.

## U.4 Real-execution observations on the updated source (fresh traces)

- `traces/follower-diff.ndjson` event 12: `NewLeaderAckSent` with `logged=1`
  and `durableZxid=-1` (no txn log on disk); the streamed txn 0x100000002 is
  appended (13), the learner processes UPTODATE and serves (14), applies (17)
  and only then makes it durable (18).
- `traces/update-diff-sync-consistency.ndjson` (the visible-diff test):
  learner s0 prepares its ACK with disk at 0x100000001 while logging
  0x100000002 (82); leader s2 counts the ACK (84) and activates epoch 2 (86);
  s0's injected UPTODATE failure sends it to LOOKING (87-88) and its LEAKED
  `SyncThread:0` makes 0x100000002 durable afterwards (89) and then dies with
  `NullPointerException ... this.learner.sock is null` ("Severe unrecoverable
  error", surefire log line 1248). Same for s1 (101-105, line 1318). s1 then
  starts an election proposing zxid 0x100000001 (in-memory), wins epoch 3 with
  s0 (106-120) and ACTIVATES epoch 3 (126) without 0x100000002, which the
  epoch-2 leader had committed and served. Only the later full restart (135+)
  reloads 0x100000002 from disk, which is why the test passes.
- Observation tests (`traces/*.observation.json`, surefire logs under
  `spec/output/update/surefire/`):
  * U1: when the NEWLEADER ACK reaches the leader, the streamed txn is in
    `pendingTxns` but not on disk (`streamedDurableWhenNewLeaderAckReceived:false`).
  * U3: a COMMIT for a proposal streamed before NEWLEADER, arriving after
    NEWLEADER, crashes the learner: `NullPointerException: Cannot read field
    "hdr" because "pif" is null at Learner.syncWithLeader`; the learner drops
    the connection, never applies the txn, while its leaked sync thread still
    logs and ACKs it.
- Exact-old controls (`old-control/`): U3 is handled normally on the old
  source (UPTODATE acknowledged, txn applied); U1 old source also ACKs before
  the txn is durable (and before it is even queued).

## U.5 Model-checking summary

Full table: `spec/output/update/campaign-summary.md` (ledger
`spec/output/update/command-results.ndjson`).

- Standard convergence (`MC.cfg`, prior bounds, depth 23): exhausted within the
  explicit depth bound, 6,608,284 distinct states, no violation of any prior
  property (bounded, not a proof).
- U1/U2: `NewLeaderAckDurable` violated in 12 states and
  `CommittedDurableOnQuorum` in 13 states from the epoch-1 aftermath family
  (reachable from MCInit, 24-step witness); the old-semantics controls violate
  both as well (pre-existing gap narrowed, not closed, by the update) -> MC-1.
- U4: `LeaderCompleteness` violated in 14 states from the reachable
  post-activation state, with and without crashes, and under full MCNext
  -> MC-2 (real execution in `update-diff-sync-consistency` events 103-126).
- U4 interaction: `SyncedLogMatchesLeader` (revised after a Case-A duplicate
  record) violated in 19 states from the reachable both-ACKed state and under
  full MCNext -> MC-3 (unchanged learner shutdown order; pre-existing).
- Full-update BFS from MCInit, focused control/completeness BFS from the
  aftermath family, open/discharge, recovery-full, base and simulations are
  budget-limited (LIMITED_COVERAGE); see the summary for their outcomes.
