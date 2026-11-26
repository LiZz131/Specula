# Incremental update analysis (Chapter 1 reconnaissance) — run incr-13b3a238967b

## Exact inputs

| Item | Identity |
|---|---|
| Old revision | artifact commit `1414ebf` ("baseline"); `/work/old-source` files byte-identical (cmp) |
| New revision | artifact commit `2efbdfc` ("update"); `/work/new-source` files byte-identical (cmp) |
| Changed files | `ZooKeeperServer.java` (M), `quorum/Learner.java` (M), `quorum/DIFFSyncConsistencyTest.java` (A) |
| Prior suite | `/work/previous/.specular-output` (exact-old V0; no unresolved findings; `spec/findings.json` empty) |
| Category | A (distributed, message passing) — unchanged; the update does not alter the thread/communication architecture, but it starts the follower SyncRequestProcessor/CommitProcessor threads earlier. |

## The source delta (both revisions read in full for the changed functions)

1. `ZooKeeperServer.startup()` is split: `startupWithServerState(State)`;
   `startupWithoutServing()` performs the full startup (session tracker,
   `setupRequestProcessors()`, throttler, JMX, metrics) but leaves
   `state = INITIAL`; `startServing()` later sets `RUNNING` (new
   `ZooKeeperServer.java:669-704`).
2. `Learner.syncWithLeader`, `case Leader.NEWLEADER` (new `Learner.java:726-762`):
   after `takeSnapshot` (SNAP/TRUNC only) and `setCurrentEpoch(newEpoch)`, the
   learner now (a) sets the socket sync timeout, (b) `setSyncMode(NONE)`,
   (c) `zk.startupWithoutServing()` (starts SyncRequestProcessor ->
   SendAckRequestProcessor and CommitProcessor threads), (d) for a follower,
   `fzk.logRequest(...)` for every buffered `packetsNotCommitted` entry and then
   `packetsNotCommitted.clear()`, and only then (e) writes the NEWLEADER ACK.
3. After the loop (new `Learner.java:765-786`): the UPTODATE ACK is written, then
   `zk.startServing()` (old: timeout, `setSyncMode(NONE)`, `zk.startup()`), then
   the remaining `packetsNotCommitted` (those received after NEWLEADER) are logged
   and all `packetsCommitted` are committed (unchanged code, changed contents).

Unchanged producers/consumers that observe the change (read in the new tree):
`FollowerZooKeeperServer.logRequest:80-89` (enqueue only: `pendingTxns.add` +
`syncProcessor.processRequest`, no fsync wait), `SyncRequestProcessor.run/flush:156-252`
(asynchronous append, batch fsync, then `SendAckRequestProcessor.processRequest:40-59`
writes `ACK(zxid)` to the leader), `Learner.writePacket:188` (shared, synchronized
output stream), `LearnerHandler.run:590-648` (after queuing NEWLEADER it reads the
*first* packet and treats any ACK as the NEWLEADER ACK, passing its zxid to
`Leader.waitForNewLeaderAck:1547-1588`, which silently ignores a mismatching zxid),
`Leader.lead:591-712` (NEWLEADER quorum -> `startZkServer` -> broadcast; the
leader's loaded log is its initial history), `Learner.syncWithLeader` COMMIT case
`:643-669` (`pif = packetsNotCommitted.peekFirst(); pif.hdr...` without null check),
`ZooKeeperServer.canShutdown:784-786` (`RUNNING || ERROR` only),
`LearnerZooKeeperServer.shutdown:155-173`, `Follower.followLeader` catch path.

## Projection onto the model vocabulary (old vs new post-state sets)

| Changed branch | Old projected effect | New projected effect | Equal? |
|---|---|---|---|
| NEWLEADER, DIFF mode | currentEpoch := e; NEWLEADER ACK sent; buffered proposals stay volatile until UPTODATE | currentEpoch := e; pipeline started (INITIAL); buffered proposals enqueued to the sync pipeline (pendingTxns + SyncRequestProcessor queue), buffer cleared; NEWLEADER ACK sent; SyncRequestProcessor may now append/fsync/ACK concurrently | **No** (queued/pendingTxns/pipeline-start/ack channel) |
| NEWLEADER, SNAP/TRUNC | snapshot; currentEpoch; ACK | snapshot; currentEpoch; pipeline started; buffered *uncommitted* proposals enqueued; ACK | **No** |
| COMMIT received after NEWLEADER, before UPTODATE | head of buffer always present for a forwarded proposal | buffer was cleared at NEWLEADER; `peekFirst()` may return null -> NPE aborts sync | **No** (new failure branch) |
| UPTODATE | ACK; mode NONE; full startup; log all buffered; commit all deferred | ACK; startServing; log only post-NEWLEADER buffered; commit all deferred | **No** |
| Follower ACK channel during sync | only NEWLEADER ACK and UPTODATE ACK are possible before UPTODATE | SyncRequestProcessor ACKs of DIFF/outstanding proposals may precede the NEWLEADER ACK on the same stream | **No** |
| Shutdown after a failure between NEWLEADER and UPTODATE | zk never started; nothing to stop | zk is INITIAL -> `canShutdown()` false -> processors leak, no drain/fast-forward | **No** (CR only, see D-6) |
| pre-Zab1.0 UPTODATE-only path | `zk.startup()` | `zk.startServing()` without `startupWithoutServing()` | changed, **outside scope** (legacy protocol; no participant of this tree sends pre-1.0) |

## Disposition

**MODEL_CHANGE_REQUIRED.** The update changes modeled follower
synchronization state, the atomicity/ordering between epoch persistence, durable
logging and the NEWLEADER ACK that feeds the leader's NEWLEADER quorum, and the
learner-to-leader packet stream consumed by an unchanged leader handler.

## Prior-model defects exposed by the projection (repairs; independent of the source delta label)

1. `CompleteSync` atomically set the follower's `durable` history to the leader's
   at sync time. In both revisions DIFF proposals are only *enqueued* to the
   asynchronous SyncRequestProcessor; durability is a later, separate step. This
   abstraction made the update's subject (durability before NEWLEADER ACK)
   unobservable.
2. `LeaderBroadcast` required followers to be in *broadcast* (post-UPTODATE).
   Source: the leader starts after a quorum of NEWLEADER ACKs
   (`Leader.lead:663-712`) and UPTODATE is sent only afterwards
   (`LearnerHandler.run:641-648`). The guard was inverted.
3. `EnterSyncPhase`/`SelectSync` required `phase[leader] = "sync"`, so a learner
   could never synchronize with an established (broadcasting) leader — the exact
   setting of the update's own test.
4. `QueueLearnerProposal`/`ObserveCommit` let a follower invent and commit a fresh
   transaction without any leader packet; `messages`/`DropMessage` modelled TCP
   packet loss without connection loss.
5. `HistoryAtLeast` compared log *lengths*; FLE compares (peerEpoch, zxid).
6. `WinElection` assigned the new epoch and guarded on the ghost
   `leadersByEpoch[ep] = {}`, making `ElectionSafety` vacuous; the source
   chooses the epoch from a quorum of connected followers (`getEpochToPropose`)
   and establishes it only after an ACKEPOCH quorum (`waitForEpochAck`).
7. `Trace.tla` did not call any base action; it rebuilt state from events, so it
   could not validate reference action semantics.
8. Single-transaction MC bounds (`Txn = {t1}`) could not express two different
   entries at one position, so `CommittedHistoriesPrefix` could not fail.

Repairs 1-4 are required for the update and its interactions; 5-7 are required
for faithful re-election after a crash and for trace replay through reference
actions; 8 is a configuration repair. All are recorded in `spec/changelog.md`.

## Chapter 5 completeness review (after generation, revisited after validation)

Source -> model: every changed branch is represented — NEWLEADER (snapshot,
epoch, mode reset, pipeline start, enqueue, buffer clear, ACK as a separate
step), UPTODATE (ACK, startServing, post-NEWLEADER enqueue, deferred commit
fold incl. its exit branch), INITIAL-state shutdown (no drain).  Unchanged
consumers whose pre-state changed are concrete: sync-loop COMMIT
(`LearnerSyncCommit`, NPE branch), LearnerHandler first-ACK read
(`LeaderReadNewLeaderAck`), SyncRequestProcessor ACK (`FsyncOne`), NEWLEADER
quorum (`LeaderBroadcast`), deferred commits (`LearnerUpToDate`,
`ReceiveCommit`).  Special call sites: the observer branch and
COMMITANDACTIVATE/INFORM(ANDACTIVATE) reconfiguration packets are unchanged and
outside the scope (no observers/reconfiguration in the model); the pre-Zab1.0
UPTODATE-only path regressed and is recorded as CR-5 (out of scope).

Model -> source: in the new states (learner INITIAL, buffer cleared, pipeline
running before the NEWLEADER ACK) the alternatives enabled by `Next` were
checked against the code: `ReceiveProposal`/`ReceiveCommit` require the
learner to be in BROADCAST (main loop), the leader's `LeaderProcessAck` only
runs after UPTODATE was queued, `FsyncOne` sends ACKs only once the current
pipeline exists, and `RoleExit` drains only RUNNING servers.  No remaining
distinguishing execution was found; trace replay of the 7 fresh traces and the
reproductions agree with these choices.  Intentional abstractions and their
limits are listed in `spec/final-result.json` (validation_limits) and
`spec/model-checking-campaign.md`.
