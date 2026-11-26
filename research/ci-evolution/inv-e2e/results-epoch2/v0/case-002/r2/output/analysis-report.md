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

# Incremental analysis — run incr-13b3a238967b (1414ebf -> 2efbdfc)

Method and isolation: only the supplied old/new sources, the artifact tree with
its two neutral commits, and the prior suite were used.  No issue tracker,
upstream history, advisory, or internet research was performed (blind
contract); the `ZOOKEEPER-3911` token appears only as a source comment in the
updated `Learner.java:748`.  Novelty of findings is therefore reported as
"not searched (blind)".

Chapter 1 projection and the disposition **MODEL_CHANGE_REQUIRED** are in
`update-analysis.md`.  The prior model needed implementation-backed repairs in
the synchronization and election abstractions before the update could be
expressed (listed there and in `spec/changelog.md`).

## Update interactions examined (Chapter 3)

* old producer -> changed Action -> old consumer: leader DIFF/NEWLEADER ->
  `LearnerNewLeader`/`LearnerAckNewLeader` -> `LeaderReadNewLeaderAck`/
  `LeaderBroadcast` (NEWLEADER quorum commits the leader's initial history).
* changed Action -> crash/recovery: currentEpoch is persisted before the
  enqueued DIFF entries are forced; FLE ranks currentEpoch before zxid, so a
  learner that crashed in that window can win the next election and TRUNC the
  committed entries away (data loss).
* changed Action -> unchanged consumer on the same stream: SyncRequestProcessor
  ACKs vs the NEWLEADER ACK read by LearnerHandler.
* unchanged COMMIT handler after the changed buffer clear: NPE.
* changed Action -> failure: INITIAL learner shutdown leak (CR).
* special/general call sites: the observer branch (`zk instanceof
  ObserverZooKeeperServer`) is unchanged and out of scope; pre-Zab1.0 path
  regressed (D-4, out of scope).

## Validation summary

Harness rebased (renamed probes, BroadcastReady moved to `startServing`, 13
update-local probes); 7 fresh new-version traces (4 prior scenarios rerun + 3
update scenarios); all replayed through reference Actions with the existential
completion property and a full-consumption witness (see `spec/changelog.md`,
`spec/output/trace-*.log`, `spec/output/trace-witness-*.log`).  Archived V0
traces are kept in `traces/archived-v0/` and are superseded by the fresh traces
of the same scenarios (their schema lacks the update fields and they were
produced by the old implementation).

## Model checking and confirmation summary

Campaign record: `spec/model-checking-campaign.md`.  Bug report:
`spec/bug-report.md`; findings index: `spec/findings.json`; confirmations:
`spec/confirmation-*.md`; reproductions: `harness/repro/`.

| ID | Property / claim | MC evidence | Implementation reproduction (new / old) | Attribution |
|---|---|---|---|---|
| MC-1 | CommittedQuorumDurable | focused, open, seeded full MCNext, replayed real trace | data loss of a served txn: FAIL / FAIL | pre-existing, not closed by the update |
| MC-2 | NewLeaderAckFirst | focused 10 states; full MCNext 58/61 states | fixture FAIL / PASS; cluster epoch not established FAIL / PASS | introduced |
| MC-3 | SyncCommitHasPendingProposal | full MCNext 60 states; focused 26 states | fixture FAIL / PASS; real cluster under load (Level 0) FAIL / PASS | introduced |
| CR-4 | INITIAL shutdown leak | trace evidence only (history effect modeled) | fixture FAIL / PASS | introduced |
| CR-5 | pre-Zab1.0 path | out of model scope | fixture FAIL / PASS | introduced |

No property was weakened; no reference Action changed after the
trace-validation gate.  Reference properties showed no violation within the
budgeted explorations (LIMITED_COVERAGE).
