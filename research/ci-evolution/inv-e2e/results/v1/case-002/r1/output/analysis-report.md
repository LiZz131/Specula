# Code analysis report — incremental run (case-002)

The V0 report (exact-old analysis) is preserved verbatim at
`spec/output/prior-v0/analysis-report-v0.md`; its architecture, election,
pipeline and persistence findings remain valid except where revised below.

## Method and isolation

Inputs: `/work/old-source`, `/work/new-source`, the neutral two-commit history in
`artifact/` (`baseline` 1414ebfb1d16fd81abc38550a96950d919ecf805 ->
`update` 2efbdfc3754df193bce05b9792297c813377cdaf), the immutable V0 suite in
`/work/previous/.specula-output`, and the ZooKeeper sources/docs inside the
artifact tree. No internet, upstream history, issue tracker, release notes or
fixed revision was consulted. Requirement statements are cited only from in-tree
documentation (`zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md`),
source comments and test assertions.

The V0 suite is treated as provisional evidence: its trace validation was a
state-projection replay (`spec/output/prior-v0/Trace-v0.tla` never called a base
action), so it did not establish that the V0 actions admit the observed runs.

## Update reconnaissance (Chapter 1)

### The diff

1. `ZooKeeperServer.startup()` becomes `startupWithServerState(RUNNING)`; new
   `startupWithoutServing()` (state INITIAL) and `startServing()` (RUNNING +
   notifyAll) (ZKS:669-696).
2. `Learner.syncWithLeader` NEWLEADER branch (L:726-761): after
   `setCurrentEpoch(newEpoch)` and `writeToTxnLog = true` it now sets the socket
   timeout, `setSyncMode(NONE)`, calls `zk.startupWithoutServing()`, hands every
   `packetsNotCommitted` record to `FollowerZooKeeperServer.logRequest`, clears the
   deque and only then writes the NEWLEADER ACK. After the loop (L:765-767) the
   learner ACKs UPTODATE and calls `zk.startServing()`; records received after
   NEWLEADER are still logged and all `packetsCommitted` are committed afterwards
   (L:777-785, unchanged).
3. New test `DIFFSyncConsistencyTest` (learners fail right after reading
   UPTODATE; all servers are restarted; the test checks the DIFF-synced
   transaction survives).

### Behavior before and after (projected on the V0 vocabulary)

| Changed branch | Old projected effect | New projected effect | Same? |
|---|---|---|---|
| DIFF records at NEWLEADER ACK | not in `queued`/`durable` of the learner | in `queued` (pending SyncRequestProcessor), not `durable` | no |
| Learner request processors at NEWLEADER ACK | none | started, server INITIAL | no (new state) |
| `syncMode` at NEWLEADER ACK | DIFF/TRUNC/SNAP | NONE | no |
| Learner failure between NEWLEADER and UPTODATE | nothing logged; `canShutdown()` false | records logged by a leaked processor; `canShutdown()` false, so no fast-forward of the data tree | no |
| UPTODATE | `startup()` (RUNNING) then log + commit | `startServing()` then log (post-NEWLEADER) + commit | timing differs |

V0 could not express any of these differences: its `CompleteSync` copied the
leader's *durable* history into the learner's durable history in one atomic
step for every mode, and its `LeaderBroadcast` waited for learners to reach the
broadcast phase rather than for NEWLEADER ACKs. Disposition:
**MODEL_CHANGE_REQUIRED** (changed state at an atomicity boundary, a newly
reachable server state, and a changed consumer-visible ordering).

### Requirement evidence for the changed behavior

- `zookeeperInternals.md:116-119` — proposals are committed when a quorum
  acknowledges them; "Acknowledgement means the server has recorded the proposal
  to persistent storage."
- `zookeeperInternals.md:192-197` — "A follower will ACK the NEW_LEADER proposal
  after it has synced with the leader"; the leader commits NEW_LEADER on a quorum
  of ACKs; followers commit the received state then.
- `zookeeperInternals.md:245-250` — a new leader has seen all committed proposals;
  uncommitted proposals it saw are committed before it becomes active.
- `Learner.java:748` (update) — "make sure sync the uncommitted logs before commit
  them (ACK NEWLEADER)".
- `DIFFSyncConsistencyTest.java:129-133, 212-214` — the ACK of NEWLEADER "makes
  leader think she has the quorum support"; assertion "Data inconsistency
  detected!".

## Representation changes (Chapter 2) and why

- `applied` is now the in-memory ZKDatabase data tree. It is the FLE vote basis
  (`QuorumPeer.getLastLoggedZxid` returns `zkDb.getDataTreeLastProcessedZxid()`,
  QP:1257-1262) and the database a new leader loads and serves
  (`ZooKeeperServer.loadData`, ZKS:480-512; `Leader.startZkServer`,
  Ldr:1497-1537). Restore (`FileTxnSnapLog.restore`) and
  `fastForwardDataBase` put logged-but-uncommitted records into it.
- `zkState` (NONE/INITIAL/RUNNING) represents the update's server-state split;
  `LearnerZooKeeperServer.shutdown` returns immediately unless RUNNING/ERROR
  (ZKS:784, LZK:155-159), so an INITIAL learner skips the fast-forward and leaks
  its SyncRequestProcessor.
- Learner session state `syncBuf` (packetsNotCommitted), `syncCommits`
  (packetsCommitted), `syncStarted`, `nlAckSent`; leader `nlAcks`
  (newLeaderProposal ack set); `epochSet` (session epoch settled).
- Fast-forward replays only records whose zxid exceeds `lastProcessedZxid`
  (FileTxnSnapLog.java:317-333); after activation a leader's marker is (epoch, 0)
  (Ldr:1536), so older logged records its data tree never applied stay
  invisible until a restart (found via the reproduction trace, event 167).
- DIFF/TRUNC/SNAP selection follows LH:775-933 against the leader's committed
  log (TRUNC when the learner is ahead of `maxCommittedLog`), found as a Case B
  by `MC.cfg` (depth 38).

## Abstractions (explicit)

- Learner shutdown order: ZKS.shutdown fast-forwards before LZK shuts down the
  SyncRequestProcessor (ZKS:845 vs LZK:166-168). The model flushes first
  (optimistic for the vote basis; recorded as CR-B).
- Snapshot persistence at NEWLEADER is treated as durable for TRUNC
  (`takeSnapshot(false)`), i.e., process-crash fault model, as in V0.
- FLE is coarse: votes accumulate per candidate; any LOOKING peer may adopt a
  candidate at least as recent as itself (including an already LEADING one).
- `leadersByEpoch` freshness guard keeps ElectionSafety structural (V0
  abstraction, unchanged in meaning).
- Duplicate appends of the same record by a leaked processor are collapsed
  (`LogSyncProposal` skips a record already in the learner pipeline).
- Observers, reconfiguration packets, sessions/ACL/payloads and the
  `isPreZAB1_0` path (UPTODATE without NEWLEADER, which now reaches
  `startServing()` without any `startup*`) are out of scope; every scoped leader
  sends NEWLEADER (LH:594-600).

## Update-focused analysis (Chapter 3)

Interactions examined (producer -> changed action -> consumer):

1. LH.syncFollower (DIFF content) -> learner NEWLEADER (log + ACK) -> leader
   waitForNewLeaderAck/startZkServer: the leader serves its whole loaded history
   once the ACK quorum forms, but the acknowledging learners have only queued the
   records; their SyncThread appends and forces them later (SRP:181-249). A crash
   in that window loses them, and the restarted learner keeps the new current
   epoch (persisted at L:743), which wins FLE comparisons (peer epoch first).
2. Learner NEWLEADER -> learner failure before UPTODATE (socket timeout, leader
   loss) -> Learner.shutdown/LZK.shutdown -> next election: the INITIAL server is
   never shut down, so its data tree (vote basis) omits the logged records; the
   leaked processor still writes them, so the log and the data tree disagree
   until restart.
3. SyncRequestProcessor ACKs for the NEWLEADER-time records may now reach the
   LearnerHandler before the NEWLEADER ACK (CR-A, liveness only).
4. `startServing` after UPTODATE: client service still starts after UPTODATE
   (unchanged externally visible point); not a safety change.

## Validation summary

- Harness: V0 patch rebased (one drifted hunk), update-local probes added, five
  scenarios (four V0 + the update's DIFFSyncConsistencyTest) plus a
  reproduction scenario derived from it (`harness/repro/`).
- Six fresh traces replay through the reference actions with TraceMatched and
  the monotonicity action property on the final reference
  (`spec/output/trace-suite-final4.ndjson`): five with all reference invariants,
  the reproduction trace with `Trace-conformance.cfg` because it exhibits the
  safety violation under study; four negative controls are rejected.
- Real-trace evidence: `CommittedPersistedOnQuorum` is violated on
  `traces/diff-sync-consistency.ndjson` right after event 94 (leader activation
  while the acknowledging learner's record is unforced); `LeaderCompleteness` is
  violated on `traces/repro-initial-state-failure.ndjson` right after event 139,
  and `CommittedHistoriesPrefix` right after event 211 (the new leader commits
  0x500000001 where the old leader had committed 0x100000002).
- Reproduction (`harness/repro/`): on the updated code, clients connected to
  both remaining servers see `exists("/zk2") = null` after the old leader had
  served `/zk2`; the baseline control fails the same way, and the update's own
  `DIFFSyncConsistencyTest` passes on both revisions in this environment.
- Model checking: see `spec/output/validation-summary.md` (all runs
  time-budgeted, LIMITED_COVERAGE; violations only for the update properties and
  for the conformance-checked reproduction).

## Findings

See `spec/bug-report.md` and `spec/findings.json` (MC-1, MC-2). Both are present
in the updated implementation; analysis indicates both mechanisms also existed
before the update (where the records were not even queued at the ACK), i.e. the
update narrows but does not close the window, and its fix is ineffective when a
failed learner is not restarted.
