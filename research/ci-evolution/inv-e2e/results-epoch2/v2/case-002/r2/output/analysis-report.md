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

## Incremental analysis for update 2efbdfc

Inputs: `/work/old-source`, `/work/new-source` (3 changed files), the neutral
two-commit artifact (`baseline` 1414ebf → `update` 2efbdfc) and the V0 prior
suite. No history, issue tracker or external source was consulted; the V0
REQ-EVIDENCE history citations are inherited text, not new research.

**Disposition: MODEL_CHANGE_REQUIRED.** The NEWLEADER handler now starts the
learner's request processors (INITIAL state) and hands every buffered sync
proposal to the asynchronous SyncRequestProcessor before writing the NEWLEADER
ACK; UPTODATE only switches the server to RUNNING. The ACK does not wait for the
fsync (`FollowerZooKeeperServer.logRequest` only enqueues, `SyncRequestProcessor`
fsyncs on its own thread). The leader counts the ACK toward the NEWLEADER quorum
that makes it serve its whole loaded history (`Leader.lead`, `startZkServer`).

**Evidence from fresh real executions.** `traces/diff-sync-uncommitted-log.ndjson`
(the update's own test, instrumented) shows, in epoch 2: learner s1
`ProposalQueued (1,2)` → `NewLeaderAck` → `TxnAppended (1,2)` → leader s2
`NewLeaderAckCounted s1` → leader `PhaseChanged broadcast` → s1 goes LOOKING →
s1 `TxnDurable (1,2)` (SyncThread still running). At the leader's activation
(1,2) is durable only at s2. TLC evaluation of `CommittedQuorumDurable` on that
replayed state is FALSE (`spec/evidence/E1-CQD/tlc.log`,
`spec/output/trace-validation/quorum-durable/`). The test passes only because
the leaked SyncThread of the failed learner keeps fsyncing; a process crash
in that window has no such thread.

**Repairs of V0 model defects** (not source-driven, needed to check the
update): learner sync no longer becomes durable instantaneously; LeaderBroadcast
counts NEWLEADER ACKs and commits the leader's initial history; unsupported
learner-originated `QueueLearnerProposal`/`ObserveCommit` removed from `Next`;
stale duplicate PROPOSAL/COMMIT messages are consumed without effect; Trace
interpretation of `ElectionWon` (winner's zxid), pre-epoch LEADING, data-tree
zxids, and restored data trees fixed. Details: `spec/changelog.md`.

**Code-review findings.** CR-2 (INITIAL-state shutdown skip after a learner
failure between NEWLEADER and UPTODATE: leaked processors, stale data tree used
for votes) and CR-3 (proposal ACK can be consumed as the NEWLEADER ACK). See
`spec/bug-report.md`.

### Results of the incremental run

- Validation: 5 fresh traces of the updated implementation replay completely
  (round r8, after all repairs); mutations M1-M4 are rejected.
- Model checking: standard MC/base canonical runs exhausted at the inherited
  level-23 bound with no violation. `CommittedQuorumDurable` is violated in the
  focused update hunt (27-state counterexample through
  `SyncWithLeaderNewLeader` → `LeaderBroadcast`); the focused action set is a
  subset of `MCNext`, so the path is a full-reference behavior.
- Reproduction (`spec/confirmation-*.md`): MC-1 REPRODUCED on 2efbdfc (and on
  the old control), CR-2 REPRODUCED (regression vs. old), CR-3 REPRODUCED
  (regression vs. old, availability only).
- Two pre-existing V0 abstractions were repaired during model checking (FIFO
  proposal delivery; one sync directive per session); see `spec/changelog.md`.
