# Analysis report — incremental update (case-002)

## Inputs and isolation
- Old: `/work/old-source` (2 changed files) and the V0 suite `/work/previous/.specula-output`
  (exact-old baseline 774296b, V0 run converged; no findings; coverage bounded).
- New: `artifact/` commit `update` 2efbdfc3754d over `baseline` 1414ebfb1d16 (neutral history).
  `diff baseline..update` = `ZooKeeperServer.java` (+14/-2), `quorum/Learner.java` (+18/-6),
  new test `DIFFSyncConsistencyTest.java`.
- No internet, upstream history, issue tracker, papers, benchmark labels or fixed revision were
  consulted. JDK 21 build/tests (as in V0); Maven Central used only for build dependencies.

## Changed mechanism (both revisions read in full: Learner.syncWithLeader, Follower.followLeader,
## FollowerZooKeeperServer.logRequest/commit, SyncRequestProcessor.run/flush/shutdown,
## ZooKeeperServer.startup*/shutdown/canShutdown, LearnerZooKeeperServer.shutdown,
## LearnerHandler.run/syncFollower, Leader.startForwarding/waitForNewLeaderAck/processAck)

Old NEWLEADER handling: snapshot if needed, `setCurrentEpoch`, ACK. Proposals buffered in
`packetsNotCommitted` were logged only after UPTODATE, after `zk.startup()`. A learner that
failed between NEWLEADER ACK and UPTODATE therefore never logged them, although the leader had
already counted its ACK towards establishing the epoch (exactly what the new
`DIFFSyncConsistencyTest` injects with a SocketTimeoutException on UPTODATE).

New NEWLEADER handling: after `setCurrentEpoch`, set socket timeout, `setSyncMode(NONE)`,
`zk.startupWithoutServing()` (processors started, State.INITIAL), `logRequest` every buffered
proposal, `packetsNotCommitted.clear()`, then the ACK. UPTODATE now only `startServing()`.

Consequences established from source (and confirmed by fresh traces):
1. `logRequest` only enqueues to SyncRequestProcessor; the ACK is written before the log is
   forced (trace `follower-diff`: `NewLeaderAcked` seq 12, `TxnDurable` seq 20;
   `update-newleader-ack-durability`: disk empty when the fixture leader reads the ACK).
2. The unchanged COMMIT case dereferences `packetsNotCommitted.peekFirst()`; a COMMIT that
   arrives after NEWLEADER for a proposal forwarded before NEWLEADER (Leader.startForwarding
   queues outstanding proposals before LearnerHandler queues NEWLEADER) finds the buffer empty ->
   NullPointerException, sync aborted (trace `update-commit-after-newleader`).
3. Shutdown from State.INITIAL is a no-op (`canShutdown()`): the processors keep running and
   flush later (good for the test's restart-from-disk check), but the data tree is not
   fast-forwarded, so `getLastLoggedZxid()` keeps the pre-sync position while
   `currentEpoch` already moved (trace `update-diff-sync-consistency` events 94-110: s1 returns to
   LOOKING with tree 0x100000001, its log later holds 0x100000002, and s1 is elected leader with
   the stale tree while the old leader s2 had committed and served 0x100000002).

## Model changes and repairs
See `spec/changelog.md` Round 0 (source-driven vs V0-defect repairs listed separately) and
`modeling-brief.md` §U. Update-focused lens: `spec/Update.tla` with full, focused, open and
discharge configurations and guided hunts.

## Validation summary
Harness rebased (one hunk re-anchored, five probes added); 7 fresh new-version traces
(4 rerun V0 scenarios + 3 update scenarios) replay with `TraceMatched` natural completion;
3 mutated negative traces rejected; archived V0 traces superseded (old ordering).
Details: `spec/output/validation-summary.md`.

## Model checking and findings
Campaigns (all budget-limited, `spec/output/mc-summary.md`): standard `MC.cfg` round 1 hit a Case A
`PipelinePrefix` mismatch (fixed, round 2: no violation to depth 29, 20.3M distinct states);
`Update-full` BFS no violation to depth 29 but its unguided simulation violated `NoSyncException`;
focused (depth 27) and open (depth 22) BFS and discharge (depth 25) found no violation; inherited
reachability canaries and the U-NPE canary were all reached. Update hunts (full MCNext plus
restricting constraints) produced actual counterexamples:

| ID | Property | Depth | Status after confirmation |
|---|---|---|---|
| MC-1 | NoSyncException (COMMIT after NEWLEADER -> NPE) | 34 / 38 (strict) | REPRODUCED, introduced by the update (old control passes) |
| MC-2 | EpochHistoryRecoverable (crash), NewLeaderAckDurable | 30 / 38 | ENV_LIMITED, pre-existing, narrowed by the update |
| MC-3 | LeaderCompleteness (no crash), EpochHistoryRecoverable (looking) | 49 / 31 | REPRODUCED (committed /zk2 lost after in-process failover), class pre-existing, not fixed by the update |

Details: `spec/bug-report.md`, `spec/findings.json`, `spec/confirmation-MC-{1,2,3}.md`,
`spec/final-result.json`.

---

# (Prior V0) Exact-old code analysis report

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
