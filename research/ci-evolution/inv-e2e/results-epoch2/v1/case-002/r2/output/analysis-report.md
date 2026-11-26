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

# Incremental analysis: case-002 update (run incr-8c80add29fe2)

## Inputs and isolation
Old snapshot `/work/old-source` and new snapshot `/work/new-source` (changed
files only), complete updated tree `artifact/` (neutral commits `baseline`,
`update`), prior suite `/work/previous/.specular-output` (immutable). No history,
issue tracker, internet research, or fixed revision was consulted. The prior
validation was converged with bounded coverage; its conclusions are reused only
where the update and the repairs below leave them applicable.

## The changed mechanism
`Learner.syncWithLeader` runs entirely on the learner thread. During DIFF sync
(`writeToTxnLog = true`, `Learner.java:614`) every PROPOSAL is buffered in
`packetsNotCommitted` and every COMMIT in `packetsCommitted`; during SNAP/TRUNC
(`writeToTxnLog = false`) committed proposals are applied to the in-memory tree
and persisted by `zk.takeSnapshot` at NEWLEADER (`:739-741`).

* Old revision: at NEWLEADER the learner persisted `currentEpoch` and wrote the
  NEWLEADER ACK; it started its request processors and called `logRequest` for
  the buffered proposals only after UPTODATE (`old Learner.java:751-775`).
* New revision: at NEWLEADER it persists `currentEpoch`, clears the sync mode,
  starts processors without serving, calls `logRequest` for every buffered
  proposal, clears the buffer, and only then writes the ACK (`Learner.java:743-760`).
  After UPTODATE it only switches the server to RUNNING (`startServing`).

`FollowerZooKeeperServer.logRequest` appends the request to `pendingTxns` and
`SyncRequestProcessor.processRequest` enqueues it (`FollowerZooKeeperServer.java:
82-89`). Append happens later on SyncThread (`SyncRequestProcessor.java:181`), and
fsync (`ZKDatabase.commit` -> `FileTxnLog.commit`) only in `flush()` (`:227-249`).
No code between `logRequest` and `writePacket(ACK)` waits for that flush.

## Consumers of the ACK (unchanged)
`LearnerHandler.run` reads the first ACK after NEWLEADER and calls
`Leader.waitForNewLeaderAck` (`LearnerHandler.java:611-623`); on a quorum the leader
runs `startZkServer` -> `zk.startup()` (`Leader.java:663-688,1497-1526`) and serves
the tree that `zk.loadData()` rebuilt from all logged transactions
(`Leader.java:593`). UPTODATE is queued only after the ACK is processed and the
leader is running (`LearnerHandler.java:641-648`).

## Prior-model repairs required by the update
1. `CompleteSync` (atomic durable install of the leader history) is replaced by
   `SelectSync` (DIFF -> volatile `syncPending`; TRUNC -> durable truncation;
   SNAP -> tentative in-memory tree in `recovered`) and `LearnerNewLeader`
   (SNAP snapshot persistence, `currentEpoch`, update hand-off).
2. `LeaderBroadcast` now consumes a quorum of NEWLEADER ACKs (`nlAcks`) and serves
   the leader's initial history (committed/applied + `everCommitted`); followers
   reach BROADCAST only after the leader started (`EnterBroadcast`).
3. `QueueLearnerProposal`/unguarded `ObserveCommit` (followers inventing or
   committing entries no leader proposed/committed) are replaced by
   `ReceiveProposal` buffering during sync and `ObserveCommit` restricted to
   leader-committed entries.
4. `Crash` restores the recoverable history (`FileTxnSnapLog.restore`: snapshot
   plus later log records); `FsyncOne` may complete without a live leader
   (shutdown flush / not-yet-serving processors); role entry requires a drained
   pipeline (`SyncRequestProcessor.shutdown` join+flush).

## Failure assumptions (unchanged)
Fail-stop crashes; fsynced log records, snapshots, and epoch files survive;
appended-but-unforced records and all queues are lost; messages may be dropped.

## Incremental validation and checking evidence (summary)
* Trace validation: 5 fresh traces of the updated implementation (prior 4 scenarios + the update's
  `DIFFSyncConsistencyTest`) pass real TLC replay with `TraceMatched` completed; an old-revision control trace
  with the same probes is rejected by the update check and accepted under the old-behaviour constant
  (`spec/validation-handoff.md`).
* Observed implementation behaviour (no injection): the NEWLEADER ACK precedes the fsync of the handed-off txn in
  every fresh DIFF trace; in the update's own 3-server test the leader starts broadcasting before the acking
  follower's `TxnDurable`.
* Model checking (`spec/model-checking-summary.md`): standard `MC.cfg` round budget-limited without violation
  (23.18 M distinct states to the depth-23 bound, 2.94 M queued; 1.17 M simulation traces); update property U1
  holds within every explored bound; U2/U3 violated from an MC-reached seed in both the focused and the full
  `MCNext` relation (finding MC-1); the old-behaviour control violates U1 and U3 (U3 without a crash).
* Reproduction: MC-1, CR-1, CR-2, CR-3 REPRODUCED (`spec/confirmation-*.md`).

## Limitations
* Bounded coverage only: 3 servers, 1 txn, ≤3 epochs, ≤2 crashes, ≤1 drop/snapshot; BFS runs stopped at their
  30-minute budgets with non-empty queues (LIMITED_COVERAGE). Simulation from `Init` did not reach the deep
  multi-epoch U2/U3 witnesses; they are established from a seed state that full `MCNext` reaches from `Init`.
* Not modeled: late joiners to a broadcasting leader, observers, reconfiguration, exception/liveness paths
  (covered by code review CR-1..CR-3), TRUNC's in-memory tree reload (visible committed/applied are not rolled
  back by `SelectSync(TRUNC)`), zxid ordering approximated by log length in FLE/`StateSummary` comparisons,
  FLE votes persist across rounds (prior abstraction; the MC-1 path does not depend on it: the same vote is admissible after the restart, and the reproduction uses real fresh FLE rounds).
* Trace coverage gaps: `SyncProposalApplied`, TRUNC directive, and a crash inside the ACK->fsync window were not
  observed in fresh harness traces (the crash window is exercised by the reproduction test instead).
* JDK 21 only (manifest prefers JDK 8/11).
