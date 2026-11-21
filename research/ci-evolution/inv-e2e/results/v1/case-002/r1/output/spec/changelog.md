# Incremental changelog (case-002: baseline -> update)

Prior V0 changelog: `spec/output/prior-v0/changelog-v0.md` (unchanged).

## Round 0 - Generation (decision gate and reference draft)

- [decision] `MODEL_CHANGE_REQUIRED`: the update changes the ordering of NEWLEADER
  handling (records handed to the async SyncRequestProcessor before the NEWLEADER
  ACK), adds the INITIAL server state on learners (startupWithoutServing), moves
  `setSyncMode(NONE)` into NEWLEADER and replaces `startup()` by `startServing()`.
  Projection onto the V0 vocabulary differs in `queued`/`durable` at ACK time,
  in the ACK-to-activation atomicity boundary and in shutdown/fast-forward
  behavior (analysis-report.md, "Update reconnaissance").
- [repair] V0 `CompleteSync` installed the leader's durable history atomically
  for DIFF (both revisions only buffer DIFF records): split into SyncDiff /
  SyncTrunc / SyncSnap + NEWLEADER (PersistCurrentEpoch, ClearSyncMode,
  StartupWithoutServing, LogSyncProposal, SendNewLeaderAck) + UPTODATE
  (StartServing, CommitSyncPacket) + EnterBroadcast.
- [repair] V0 `LeaderBroadcast` counted followers in broadcast phase; the leader
  activates on a quorum of NEWLEADER ACKs (ReceiveNewLeaderAck, LeaderActivate)
  and serves (commits) its whole loaded data tree (Ldr:1497-1537).
- [repair] Election split to the probe-observable steps (WinElection /
  FollowLeader / StartLeading / StartFollowing / LeaderProposeEpoch / AcceptEpoch /
  SendAckEpoch / LeaderPersistEpoch / LeaderStartSync); vote basis is the
  in-memory data tree (`applied`) per QP:1257-1262; ACKEPOCH "more recent" check.
- [repair] Crash clears volatile committed/applied; Restart restores the
  persisted history (snapshot + log). `recovered` removed (subsumed by `applied`).
- [props] ServingApplyCommitted replaces ApplyRequiresCommitCertificate;
  OneActiveLeaderPerEpoch migrated to established leaders; SyncCompletionJustified
  strengthened (NEWLEADER ACK); PipelinePrefix snapshot clause for live servers;
  new Update properties CommittedPersistedOnQuorum and LeaderCompleteness
  (spec/invariant-evidence.json).
- [preflight] SANY clean; static VAV check found 11 missing frames for the new
  `syncStarted` variable, fixed (spec/output/gen-preflight-vav.log); cfg
  operator check clean (spec/output/gen-preflight-cfg.log).

## Round 1 - Trace Validation

- [harness] Rebased V0 patch: only the `BroadcastReady` hunk drifted (now after
  `zk.startServing()`); added update-local probes ZkStartup, NewLeaderAckSent,
  UpToDateReceived, NewLeaderAckReceived, SyncProposalReceived,
  SyncCommitReceived, LeaderProposed, AckReceived, LeaderCommitted and a config
  line; added scenario `diff-sync-consistency` (the update's own test).
- [fix-capture] CommitDelivered moved before `commitProcessor.commit` (TxnApplied
  could precede it). (Trace: quorum-startup-mutation-shutdown, run 1)
- [fix-capture] NewLeaderAckSent moved before the socket write and LeaderCommitted
  before `commit(zxid)`; ZkStartup before `setState` (receiver probes preceded
  sender probes). (Trace: leader-abandon-restart-recovery run 1, events 30/31,
  164-166). Run-1 traces kept as `traces/superseded-run1/`.
- [fix-capture] ElectionWon now records the chosen leader id; FollowLeader is
  determined by it (removes dead branches that broke universal TraceMatched).
- [fix-spec] BeginElection no longer resets syncMode (only L:564-590/L:750 write
  it); new `syncStarted` session flag. (diff-sync-consistency)
- [fix-spec] INITIAL-state failure: no fast-forward and the started
  SyncRequestProcessor keeps writing (AppendOne/FsyncOne enabled after the
  session ends). (diff-sync-consistency events 96-98, 113-115)
- [fix-spec] RestartElectionRound for LOOKING re-assertion (QP LOOKING case).
- [fix-spec] CastVote: a LOOKING voter may adopt an already-LEADING candidate
  (FLE:1055-1080 outofelection). (diff-sync event 126, leader-abandon event 273)
- [fix-trace] ElectionWon zxid is the leader's vote or the peer's own proposal
  (outofelection path). (leader-abandon event 274)
- [result] All five fresh traces pass with TraceMatched + all reference
  invariants + HistoryPositionsMonotonicExceptRecovery
  (spec/output/trace-suite-final1.ndjson). Negative controls rejected.

## Round 1 - Model Checking (provisional) and repair back-edges

- [bug-candidate] CommittedPersistedOnQuorum violated on the real trace
  diff-sync-consistency (event 94) and by TLC from FocusInit (20 states).
- [bug-candidate] LeaderCompleteness violated from FocusInit2 (INITIAL-state
  failure, no crash) and in the crash variant (ACTION_CONSTRAINT
  NoInitialStateFailure).
- [repro] harness scenario `repro-initial-state-failure`: on the updated code
  the new leader's database lacks the committed /zk2 (assertion failure);
  attempt-1 trace exposed:
- [fix-spec] Fast-forward replays only records with zxid > lastProcessedZxid;
  after activation that is (epoch, 0) (Ldr:1536, FileTxnSnapLog.java:317-333):
  FastForwardFloor/FastForwardReplay. Leader history = committed + outstanding
  current-epoch proposals; Commit and FIFO guards use current-epoch order.
  (repro attempt-1 event 167)
- [fix-spec] Case B from MC.cfg (C1, depth 38, ServingApplyCommitted): SyncDiff
  admitted a learner whose data tree held an uncommitted fast-forwarded record;
  LH:845-853 sends TRUNC when peerLastZxid > maxCommittedLog. DIFF/SNAP guards
  now use the leader's committed log.
- [result] Six fresh traces (incl. repro) pass on the repaired reference
  (spec/output/trace-suite-final3.ndjson). Campaigns C1/C2a/C2b/C4/C6 ran on
  the pre-repair model and are recorded as provisional; final campaigns R*
  rerun on the repaired model (see bug-report.md and validation summary).

## Round 2 - Trace Validation (reproduction attempt 3) and final regression

- [fix-spec] Sticky epoch-ACK quorum (`ElectionFinished`): Ldr:1442-1466 sets
  `electionFinished` once, using each learner's ACKEPOCH-time summary; the model
  re-evaluated "more recent" after the learner had persisted the new epoch.
  (repro attempt-3 event 137: leader persists its epoch after the learner's
  whole NEWLEADER exchange)
- [fix-spec] Per-session `pending` queue (FZK:80 pendingTxns): a follower's
  COMMIT matches the head of the current FollowerZooKeeperServer's queue, not
  the whole log (a leaked earlier session may have logged extra records).
  (repro attempt-3 event 212)
- [trace-cfg] `Trace-conformance.cfg` for the reproduction trace: all actions,
  post-state checks, TraceMatched and structural invariants; the protocol
  safety invariants it violates (CommittedHistoriesPrefix at event 211,
  LeaderCompleteness at event 139) are recorded as evidence
  (`spec/evidence/trace-A2/`).
- [result] Final trace regression on the final reference: six traces pass
  (`spec/output/trace-suite-final4.ndjson`); final campaign Z* started at
  2026-11-18T21:52:06Z on the files hashed in `spec/output/FINAL_MODEL_SHA256`.
