# Code analysis report — incremental update (case-002)

## Incremental update (artifact `1414ebf` baseline → `2efbdfc` update)

### Inputs and method
- Old/new changed-file snapshots (`/work/old-source`, `/work/new-source`) and the artifact's
  two neutral commits; prior V0 suite `/work/previous/.specula-output` (immutable).
- Analysis is source-only: changed functions were read in both revisions together with their
  callers, callees, tests and consumers (Learner, Follower, LearnerZooKeeperServer,
  FollowerZooKeeperServer, ZooKeeperServer, SyncRequestProcessor, SendAckRequestProcessor,
  LearnerHandler, Leader, QuorumPeer, ZKDatabase, FileTxnSnapLog, FileTxnLog). No history,
  issue tracker, internet or later revision was consulted.
- Category unchanged: **A (distributed, message passing)**.

### The source delta
1. `ZooKeeperServer.startup()` is split into `startupWithServerState(state)`;
   `startupWithoutServing()` starts session tracker and request processors but leaves the
   server in `State.INITIAL`; `startServing()` sets `RUNNING` (ZooKeeperServer.java:669-704).
2. `Learner.syncWithLeader`, NEWLEADER branch (Learner.java:726-760): after the optional
   snapshot and `setCurrentEpoch`, the learner now sets the socket timeout, `setSyncMode(NONE)`,
   calls `zk.startupWithoutServing()`, hands every buffered `packetsNotCommitted` entry to
   `fzk.logRequest`, clears the buffer and only then writes ACK(newLeaderZxid).
3. After the loop (UPTODATE, Learner.java:762-786): `writePacket(ack)`, `zk.startServing()`
   (previously `setSoTimeout`, `setSyncMode(NONE)`, `zk.startup()`), then — unchanged — log
   the remaining buffered packets and `fzk.commit` every `packetsCommitted` zxid.
4. New test `DIFFSyncConsistencyTest` (followers fail when reading UPTODATE after a DIFF sync,
   then **all servers are restarted**; the test checks the new leader still has the txn).

### Decision gate (Chapter 1): `MODEL_CHANGE_REQUIRED`
Projection on the existing vocabulary: at the modeled NEWLEADER step the new code moves the
DIFF suffix into the txn-log pipeline (`queued`) and starts the server instance, before the
NEWLEADER ACK; the old code did both only after UPTODATE.  The post-state of an existing
modeled step (queued history, server start, sync mode reset) differs, and the update's purpose
is a correctness requirement (a NEWLEADER quorum must certify the synchronized history).  The
prior model could not express this: its `CompleteSync` made the leader history instantly
durable, `LeaderBroadcast` waited for followers in BROADCAST (after UPTODATE) instead of
NEWLEADER ACKs, the leader's recovered log was never committed, and votes compared txn logs
instead of the DataTree position.  These prior abstractions were repaired (changelog
"Round 1 — Generation").

### Key implementation facts established for the update
- `FollowerZooKeeperServer.logRequest` only enqueues to the SyncRequestProcessor
  (FollowerZooKeeperServer.java:82-90; SyncRequestProcessor.java:290-296).  Append, flush and
  fsync run on the SyncThread (SyncRequestProcessor.java:155-251).  **The NEWLEADER ACK is not
  ordered after the fsync.**  Fresh trace `follower-diff` shows `NewLeaderAckSent` (seq 13)
  long before `TxnDurable` of the same zxid (seq 21+).
- `Leader.waitForNewLeaderAck` counts the ACK; with a quorum the leader runs `startZkServer`
  and serves its whole loaded tree (Leader.java:661-688, :1497-1536).  The loaded tree includes
  txns that were only in the leader's log (ZooKeeperServer.loadData / FileTxnSnapLog.restore).
- `ZooKeeperServer.shutdown(boolean)` and `LearnerZooKeeperServer.shutdown()` return
  immediately unless `canShutdown()` (RUNNING or ERROR) (ZooKeeperServer.java:784-807,
  LearnerZooKeeperServer.java:155-159).  With the update, a learner that fails between
  NEWLEADER and UPTODATE is in `INITIAL` with running processors: shutdown is skipped, the
  DataTree is **not** fast-forwarded from the log, the SyncRequestProcessor keeps running and
  later flushes the logged txns.  Fresh trace `diff-sync-uptodate-failure` shows
  `ZkShutdownSkipped` (aux.zkState=INITIAL, tree 1.1, log tail 1.2) followed by LOOKING with
  zxid 1.1 and a late `TxnDurable 1.2` from the leaked SyncThread.
- `QuorumPeer.getLastLoggedZxid` returns the DataTree position (QuorumPeer.java:1257-1262) and is
  used for FLE votes and FOLLOWERINFO; `Leader.lead → loadData` reuses an initialized tree
  (ZooKeeperServer.java:480-503).  A peer with a stale tree therefore advertises and, if elected
  in-process, serves a history without the logged txns.  Superseded harness run attempt 3
  (`traces/superseded-attempt3/diff-sync-uptodate-failure.ndjson` seq 120-143) shows such peers
  re-electing in-process (s1 LEADING with zxid 1.1, epoch 3 accepted by s1 and s0) after the
  epoch-2 leader had served 1.2.
- Because processors start at NEWLEADER, `SendAckRequestProcessor` can send per-txn ACKs
  before the NEWLEADER ACK; `LearnerHandler` treats the first ACK as the NEWLEADER ACK and
  `Leader.waitForNewLeaderAck` ignores a mismatched zxid (LearnerHandler.java:611-623,
  Leader.java:1555-1563).  Availability only; recorded as code-review item CR-3.

### Update scenarios (see `modeling-brief.md` §2 U-1..U-4)
| Scenario | Path | Model actions | Expected/checked |
|---|---|---|---|
| U-1 ACK durability | old producer (DIFF stream) → NEWLEADER log+ACK → leader quorum → crash | SyncWithLeader, LearnerLogPendingOne, LearnerSendNewLeaderAck, LeaderStartZkServer, FsyncOne, Crash, Restart | NewLeaderAckImpliesDurable, AckedHistoryRetained, LeaderCompleteness |
| U-2 skipped shutdown | NEWLEADER ACK → UPTODATE failure → shutdown in INITIAL → in-process election | ServerShutdown, CastVote/WinElection, SyncWithLeader | AckedHistoryRetained, LeaderCompleteness, CommittedHistoriesPrefix |
| U-3 UPTODATE path | ACK → leader serving → UPTODATE → startServing → log/commit buffered | LearnerUptodate* , ReceiveProposal/Commit (sync), ApplyOne | ServingApplyRequiresCommitCertificate, SyncCompletionJustified |
| U-4 restart path (test) | ACK → failure → process restart → re-election | Crash, Restart, elections | LeaderCompleteness (reachable, expected to hold) |

### Abstractions and limits (update-relevant)
- Txn-log "durable" means fsynced (power-loss semantics, as in the prior model).  Data flushed
  to the OS survives a process kill; a process kill between ACK and the SyncThread's buffer
  flush loses it, a power loss before fsync loses it as well.
- Election is abstracted to per-round vote sets with FLE's (epoch, zxid) order on
  `LastLogged`; votes are withdrawn on role exit/crash (repair).  Server-id tie-breaks are not
  modeled (any tie may win).
- Observers, reconfiguration, sessions/digests and payload semantics remain out of scope.
  Duplicate log entries after a stale-tree re-DIFF are represented as repeated entries.

---

# Prior V0 report (exact-old baseline, retained for reference)

## Exact-old code analysis report

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
