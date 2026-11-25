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

# Incremental update analysis (case-002, neutral commits `baseline` -> `update`)

## U1. Exact inputs (Chapter 1 reconnaissance)

- Old revision: neutral commit `baseline` (`1414ebfb1d16fd81abc38550a96950d919ecf805`); new revision:
  neutral commit `update` (`2efbdfc3754df193bce05b9792297c813377cdaf`) in
  `artifact/`. `/work/old-source` and `/work/new-source` are byte-identical to the
  two commits for the three changed files.
- Changed files: `ZooKeeperServer.java` (startup split), `quorum/Learner.java`
  (`syncWithLeader` NEWLEADER/UPTODATE handling), and a new test
  `quorum/DIFFSyncConsistencyTest.java`.
- Prior suite: `/work/previous/.specula-output` (V0, exact-old). No prior findings; prior
  validation unresolved errors: none reported. Prior coverage limits retained (finite
  bounds, level-23 canonical constraint, JDK 21).
- Category A (unchanged): the update does not change the communication architecture;
  it changes the ordering of persistence, server-startup state, and acknowledgement
  inside the existing learner thread, and the start time of the follower's independent
  `SyncRequestProcessor`/`CommitProcessor` threads.

## U2. Changed behavior (old vs new), per branch

`Learner.syncWithLeader`, NEWLEADER case (`Learner.java:726-761` new, `:726-747` old):

| Step | old | new |
|---|---|---|
| snapshot for SNAP/TRUNC (`:739-741`) | before `setCurrentEpoch` | unchanged |
| `setCurrentEpoch(newEpoch)` (`:743`) | before ACK | unchanged |
| `setSyncMode(NONE)` | after UPTODATE (`old :754`) | at NEWLEADER, before ACK (`new :750`) |
| request processors (`SyncRequestProcessor`, `CommitProcessor`) | started by `zk.startup()` after UPTODATE (`old :755`) | started by `zk.startupWithoutServing()` at NEWLEADER (`new :751`, `ZooKeeperServer.java:673-704`), server state `INITIAL` |
| buffered `packetsNotCommitted` (DIFF payload and outstanding proposals) | handed to `fzk.logRequest` only after UPTODATE (`old :766-770`) | handed to `fzk.logRequest` before the NEWLEADER ACK (`new :752-758`), then cleared |
| NEWLEADER ACK (`writePacket`) | `old :746` | `new :760` |
| after UPTODATE | ACK, `setSyncMode(NONE)`, `zk.startup()` (RUNNING) | ACK, `zk.startServing()` (`ZooKeeperServer.java:677-680`, RUNNING) |
| post-UPTODATE log/commit loop | logs all buffered packets, commits `packetsCommitted` | logs only packets buffered after NEWLEADER, commits all `packetsCommitted` |

`fzk.logRequest` (`FollowerZooKeeperServer.java:82-89`) only appends to
`pendingTxns` and enqueues on `SyncRequestProcessor.queuedRequests`; the append
(`SyncRequestProcessor.java:181`) and the fsync (`:235`, `ZKDatabase.commit`) run on
the independent `SyncThread`, which only afterwards forwards each request to
`SendAckRequestProcessor` (`:245`). Nothing between `new :752-758` and the ACK write at
`new :760` waits for that thread. Hence in the new revision the NEWLEADER ACK may be
written while the DIFF transactions are queued (or appended but unforced) and not
durable.

Projection onto the V0 vocabulary:

- DIFF branch: the old projected post-state of NEWLEADER keeps the DIFF suffix only in
  a learner-local buffer; the new post-state has it in `proposed/queued` (pending
  `SyncRequestProcessor`) with `durable` unchanged. The V0 model's `CompleteSync`
  copies `durable[l]` into `durable[s]` atomically, which matched neither revision.
  Projected post-states differ (queued vs buffered; processor start; sync-mode reset
  ordering) => model change.
- SNAP/TRUNC branches: durable history is installed before the ACK in both revisions
  (TRUNC: `truncateLog` at the directive; SNAP: `takeSnapshot(syncSnapshot=true)` at
  `:739-741`). Only proposals buffered in `packetsNotCommitted` (outstanding proposals)
  change from "logged after UPTODATE" to "queued before ACK".
- Server lifecycle: new `INITIAL` state between NEWLEADER and UPTODATE. In that state
  `ZooKeeperServer.canShutdown()` is false (`ZooKeeperServer.java:784-786`), so
  `LearnerZooKeeperServer.shutdown()` (`quorum/LearnerZooKeeperServer.java:155-173`)
  returns without shutting down/flushing `SyncRequestProcessor` and without
  `zkDb.fastForwardDataBase()` (`ZooKeeperServer.java:836-850`). Old revision: no
  processors existed in that window.

## U3. Implementation-backed defects in the reused abstraction (repairs)

1. `LeaderBroadcast` required a quorum of followers already in public BROADCAST.
   `Leader.lead` (`Leader.java:660-712`) only waits for a NEWLEADER-ACK quorum
   (`waitForNewLeaderAck`, `:1547-1586`); `LearnerHandler` sends UPTODATE only after
   `learnerMaster.waitForStartup()` (`LearnerHandler.java:621-648`). The prior trace
   `quorum-startup-mutation-shutdown.ndjson` already shows the leader entering
   broadcast (seq 16) before the follower does (seq 19). The V0 observational trace
   spec hid this mismatch. Repair: explicit NEWLEADER ACK counting.
2. `LeaderBroadcast` did not make the leader's own history committed/visible although
   `startZkServer` serves the leader's data tree loaded from its full log
   (`Leader.java:592`, `ZooKeeperServer.loadData :480-511`) and the internals document
   requires the new leader to commit its history before it becomes active
   (`zookeeperInternals.md:196-198, :243-249`).
3. `EnterSyncPhase`/`SelectSync` required the leader to be in public SYNC; the
   LearnerHandler syncs as soon as the epoch-ACK quorum releases `waitForEpochAck`,
   concurrently with the leader thread's `setCurrentEpoch/setZabState(SYNC)`
   (prior trace seq 10-14), and late joiners sync with an already BROADCAST leader.
4. `ObserveCommit` self-certified a learner-side commit and `QueueLearnerProposal`
   fabricated a fresh learner transaction; neither has an implementation path
   (learner COMMITs come only from the leader's committed log/`tryToCommit`).

## U4. Decision

**Disposition: `MODEL_CHANGE_REQUIRED`.** The update changes modeled persistence
ordering, the request-processor lifecycle (atomicity/state boundary), the projected
post-state of the NEWLEADER step, and the correctness obligation stated by the update
itself ("make sure sync the uncommitted logs before commit them (ACK NEWLEADER)",
`Learner.java:748`). Repairs U3.1-U3.4 are recorded separately as old-model defects
that the update interacts with.

Old Scenarios to recheck: Scenario 2 (DIFF/TRUNC/SNAP) and Scenario 3/4 (pipeline,
crash/restart). Prior findings: none. Exclusions retained (observers, reconfig,
sessions, byte formats).

## U5. Update-focused deep analysis (Chapter 3)

Interaction paths, each tied to model Actions and evidence:

| Path | Code | Model Actions | Uncertainty / consequence | Evidence |
|---|---|---|---|---|
| old producer (leader log) -> changed NEWLEADER handling -> old consumer (leader activation) | `LearnerHandler.syncFollower`, `Learner.java:748-760`, `Leader.java:1547-1586, 660-712` | SelectSync, CompleteSync, PersistCurrentEpoch, ClearSyncMode, LogSyncProposal, AckNewLeader, CountNewLeaderAck, LeaderBroadcast | ACK counted while DIFF suffix only queued -> history activated without quorum durability | traces `follower-diff*`, `diff-sync-uncommitted-log`; MC-1 |
| changed Action -> crash/recovery | `SyncRequestProcessor` async flush; fail-stop crash | AckNewLeader, Crash, Restart, next election | queued suffix lost after the ACK was counted | model (`UpdLostCommitSpec`, MaxCrash 1) |
| changed Action -> failure -> old consumer (election) | `ZooKeeperServer.java:784-786, 803-850`; `LearnerZooKeeperServer.java:155-173`; `QuorumPeer.java:1257-1262`; `Leader.java:592` | ClearSyncMode (INITIAL), BeginElection (no drain/fast-forward), CastVote/WinElection on `recovered`, LeaderBroadcast | a learner whose log holds the activated history votes/leads with an older in-memory database | trace `diff-sync-uncommitted-log` seq 82-102 (and r1 seq 98); MC-2 |
| changed Action -> retry (next sync of the same learner) | `Learner.registerWithLeader` reports the in-memory zxid | SelectSync/CompleteSync with `recovered` | DIFF re-sends already-logged txns (duplicate log records) | code review; not a safety property here |
| changed Action -> changed Action (two SyncRequestProcessor ACK paths) | `SendAckRequestProcessor`, `LearnerHandler.java:610-623`, `Leader.java:1555-1563` | not modeled | proposal ACK read as NEWLEADER ACK -> learner not counted (liveness) | CR-1; probe `NewLeaderAckMismatch` (0 hits) |

Reused assumptions rechecked: (a) the vote position is the in-memory database,
not the log (V0 used the log length; repaired); (b) a learner's data tree equals
its log at the next election only after a RUNNING shutdown (V0 implicit; now
explicit and violated by the new INITIAL state); (c) learner COMMIT is evidence of
a leader certificate (kept, but no longer self-certifying).

Prior findings lineage: V0 reported none; no masks to re-examine.

## U6. Property decisions (Chapter 3 §3, Divergence Evidence)

Recorded in `spec/invariant-evidence.json` (initial decisions unchanged by the
observations): three added requirement properties in `Update.tla`
(`UpdNewLeaderAckAfterDurable`, `UpdEstablishedHistoryDurableOnQuorum`,
`UpdLeaderCompleteness`), all with TLC-evaluated separating states from real traces
or MC and passing controls; six affected V0 properties kept with a shared
trace-state evaluation (old and new definitions both TRUE); `ElectionSafety`
kept as the unaffected control. All three added properties are bug candidates
(implementation produces the forbidden state), so none was edited toward the
implementation.

## U7. Validation summary

See `spec/output/validation-handoff.md`: rebased harness, 8 fresh new-version
traces (5 regression scenarios incl. three DIFF repetitions + update scenario
`DIFFSyncConsistencyTest`), all fully replayed by `Trace.tla`
(`spec/output/trace/r4-*.log`), archived V0 traces superseded.

## U8. Persistent findings and history

The prior run recorded no findings, and the `specular findings` helper is not installed in
this environment, so no historical record could be looked up or reused; MC-1, MC-2 and CR-1
are new in this run. No repository history, issue tracker or later revision was consulted.

## U9. Completeness review (Chapter 5)

Source diff reread against the final suite:

| Change | Reference surface | Update.tla | Validation |
|---|---|---|---|
| `startup()` split into `startupWithServerState(RUNNING/INITIAL)`, `startServing()` (ZooKeeperServer.java:669-704) | `zkState`, `ClearSyncMode` (INITIAL), `ReceiveUpToDate` (RUNNING), `LeaderBroadcast` (leader RUNNING), `BeginElection` (drain/fast-forward only if RUNNING) | AffectedActions, InteractionActions (BeginElection) | BroadcastReady checks `zkState`; diff-sync seq 97-102 |
| `sock.setSoTimeout(syncLimit)` moved before the ACK (Learner.java:749) | timing not modeled; any learner may leave sync at any time (`BeginElection`) | n/a | trigger noted for MC-2 |
| `setSyncMode(NONE)` moved before the ACK (Learner.java:750) | `ClearSyncMode` guard (after `PersistCurrentEpoch`, before `AckNewLeader`) | AffectedActions | SyncModeChanged(NONE) replayed in every sync |
| `logRequest(packetsNotCommitted)` + `clear()` before the ACK (Learner.java:752-757) | `LogSyncProposal` (NEWLEADER window), `AckNewLeader` requires the buffer handed over | AffectedActions | ProposalQueued before NewLeaderAckSent (DIFF traces) |
| NEWLEADER ACK (Learner.java:760) | `AckNewLeader`, `CountNewLeaderAck` | AffectedActions, UpdNewLeaderAckAfterDurable | NewLeaderAckSent/Counted replayed |
| `zk.startServing()` after UPTODATE ACK (Learner.java:767) | `ReceiveUpToDate` | AffectedActions | BroadcastReady replayed |
| post-UPTODATE loop logs only post-NEWLEADER packets, commits all (Learner.java:777-786) | `LogSyncProposal` (running), `ObserveCommit`, `ReceiveCommit` (running) | AffectedActions / InteractionActions | follower-snap ProposalQueued after BroadcastReady |
| new test `DIFFSyncConsistencyTest` | harness scenario `diff-sync-uncommitted-log` | U-Scenario 1/2 | 136-event trace replayed |

Model-to-source check in the new INITIAL state: enabled alternatives are leaving the round
(`BeginElection`, no drain/fast-forward), `Crash`, buffering proposals, SyncThread
append/fsync; commits are applied only after UPTODATE (`ObserveCommit`/`ReceiveCommit` guarded
by RUNNING) - matching `syncWithLeader`, which buffers COMMITs until UPTODATE. Unchanged code
paths with changed meaning (vote zxid = in-memory database; RUNNING-only drain/fast-forward;
leader activation on NEWLEADER ACKs) were repaired and are listed in U3 and `spec/changelog.md`.
No unresolved semantic gap remains within the scope; limits: TRUNC not traced, CR-1 not
modeled, election/discovery observed rather than replayed.
