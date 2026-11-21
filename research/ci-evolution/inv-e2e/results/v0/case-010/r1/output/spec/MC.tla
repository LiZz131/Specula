------------------------------- MODULE MC -------------------------------
EXTENDS base

(***************************************************************************)
(* Finite exploration driver for the updated reference. Fault-injection    *)
(* actions are counter bounded; reactive actions are not. Bounds limit     *)
(* executions; results are LIMITED_COVERAGE, never proof.                  *)
(***************************************************************************)

CONSTANTS TrackCoverage, MaxRounds, MaxCrashes, MaxExits, MaxSnapshots

VARIABLES counters, seen

mcvars == <<vars, counters, seen>>

MCInit ==
    /\ Init
    /\ counters = [rounds |-> 0, crashes |-> 0, exits |-> 0, snapshots |-> 0]
    /\ seen = {}

\* Coverage marks double as Scenario reachability canaries.
Mark(names) == seen' = IF TrackCoverage THEN seen \cup names ELSE seen

NoMark == UNCHANGED seen

-----------------------------------------------------------------------------
(* Election and discovery *)

MCBeginElection ==
    /\ counters.rounds < MaxRounds
    /\ BeginElectionRound
    /\ counters' = [counters EXCEPT !.rounds = @ + 1]
    /\ NoMark

MCCastVote(v, c) == CastVote(v, c) /\ UNCHANGED counters /\ NoMark

MCFinishElection(s, c) ==
    /\ FinishElection(s, c)
    /\ UNCHANGED counters
    /\ Mark(IF role[c] = "LEADING" /\ s # c THEN {"JoinEstablishedLeader"}
            ELSE {"FinishElection"})

MCEnterDiscovery(s) == EnterDiscovery(s) /\ UNCHANGED counters /\ NoMark

MCLeaderProposeEpoch(l) == LeaderProposeEpoch(l) /\ UNCHANGED counters /\ NoMark

MCPersistFollowerAccepted(f) == FollowerPersistAcceptedEpoch(f) /\ UNCHANGED counters /\ NoMark

MCRecordEpochAck(l, f) ==
    /\ f # l
    /\ RecordEpochAck(l, f) /\ UNCHANGED counters /\ NoMark

MCLeaderEpochQuorum(l) == LeaderEpochQuorum(l) /\ UNCHANGED counters /\ NoMark
MCLeaderStartSync(l) == LeaderStartSync(l) /\ UNCHANGED counters /\ NoMark

-----------------------------------------------------------------------------
(* Learner synchronization *)

MCEnterFollowerSync(f) == EnterFollowerSync(f) /\ UNCHANGED counters /\ NoMark

MCChooseSync(f, m) ==
    /\ ChooseSyncMode(f, m) /\ UNCHANGED counters
    /\ Mark({"Choose" \o m})

MCApplySnapshot(f) == LearnerApplySnapshot(f) /\ UNCHANGED counters /\ Mark({"ApplySnapshot"})
MCTruncateLog(f) == LearnerTruncateLog(f) /\ UNCHANGED counters /\ Mark({"TruncateLog"})
MCSyncPacket(f, t) == LearnerSyncPacket(f, t) /\ UNCHANGED counters /\ NoMark

MCSyncCommit(f) ==
    /\ LearnerSyncCommit(f) /\ UNCHANGED counters
    /\ Mark(IF syncMode[f] \in {"SNAP", "TRUNC"} /\ syncStage[f] = "DATA"
            THEN {"InMemorySyncCommit" \o syncMode[f]} ELSE {})

MCSyncSnapshot(f) == LearnerSyncSnapshot(f) /\ UNCHANGED counters /\ NoMark
MCPersistFollowerCurrent(f) == LearnerPersistCurrentEpoch(f) /\ UNCHANGED counters /\ NoMark
MCNewLeaderModeNone(f) == LearnerNewLeaderModeNone(f) /\ UNCHANGED counters /\ NoMark
MCAckNewLeader(f) == LearnerAckNewLeader(f) /\ UNCHANGED counters /\ NoMark
MCFormNewLeaderQuorum(l) == FormNewLeaderQuorum(l) /\ UNCHANGED counters /\ NoMark

MCLeaderBroadcast(l) == LeaderEnterBroadcast(l) /\ UNCHANGED counters /\ NoMark

MCUpToDate(f) == LearnerUpToDate(f) /\ UNCHANGED counters /\ NoMark
MCCompleteSync(f) == CompleteLearnerSync(f) /\ UNCHANGED counters /\ Mark({"CompleteSync"})

MCFollowerBroadcast(f) == FollowerEnterBroadcast(f) /\ UNCHANGED counters /\ NoMark

-----------------------------------------------------------------------------
(* Broadcast pipeline *)

MCLeaderPropose(l) ==
    /\ nextTxn \in Txn /\ LeaderPropose(l, nextTxn)
    /\ UNCHANGED counters /\ NoMark

MCFollowerPending(f, t) == FollowerPendingProposal(f, t) /\ UNCHANGED counters /\ NoMark
MCQueue(s, t) == QueueForSync(s, t) /\ UNCHANGED counters /\ NoMark
MCFlush(s, t) == FlushTxnLog(s, t) /\ UNCHANGED counters /\ NoMark
MCAck(l, src, t) == RecordProposalAck(l, src, t) /\ UNCHANGED counters /\ NoMark
MCCommit(l, t) == CommitProposal(l, t) /\ UNCHANGED counters /\ Mark({"Commit"})
MCFollowerCommit(f, t) == FollowerCommit(f, t) /\ UNCHANGED counters /\ NoMark
MCApply(s, t) == ApplyTxn(s, t) /\ UNCHANGED counters /\ NoMark

MCBeginSnapshot(s) ==
    /\ counters.snapshots < MaxSnapshots
    /\ phase[s] = "BROADCAST"
    /\ BeginSnapshot(s)
    /\ counters' = [counters EXCEPT !.snapshots = @ + 1]
    /\ NoMark

MCFinishSnapshot(s) == FinishSnapshot(s) /\ UNCHANGED counters /\ Mark({"FinishSnapshot"})

-----------------------------------------------------------------------------
(* Faults, exits, recovery *)

MCCrash(s) ==
    /\ counters.crashes < MaxCrashes
    /\ Crash(s)
    /\ counters' = [counters EXCEPT !.crashes = @ + 1]
    /\ NoMark

MCRestart(s) ==
    /\ ~running[s]
    /\ RestartLoadDatabase(s, acceptedEpoch[s], currentEpoch[s])
    /\ UNCHANGED counters /\ Mark({"Restart"})

LeaderAlive(f) ==
    leaderOf[f] \in Server /\ running[leaderOf[f]] /\ role[leaderOf[f]] = "LEADING"

\* Learner exit. With a live leader it is an injected fault (read timeout,
\* I/O error, the update test's NEWLEADER exception) and is bounded; when the
\* leader is gone it is the reactive socket failure and is not bounded.
MCLearnerShutdown(f) ==
    /\ running[f]
    /\ IF LeaderAlive(f)
       THEN /\ counters.exits < MaxExits
            /\ counters' = [counters EXCEPT !.exits = @ + 1]
       ELSE UNCHANGED counters
    /\ LearnerShutdown(f)
    /\ Mark(
         (IF syncMode[f] = "SNAP" /\ syncStage[f] \in {"MODE", "DATA"}
          THEN {"SnapAbortBeforeNewLeader"} ELSE {})
         \cup (IF syncMode[f] = "TRUNC" /\ syncStage[f] = "DATA"
                  /\ ~(Elems(memDb[f]) \subseteq Elems(durable[f]))
               THEN {"TruncAbortWithMemoryOnlyCommit"} ELSE {})
         \* after NEWLEADER the code has already reset syncMode to NONE
         \* (Learner.java:750); the stage identifies the window
         \cup (IF syncStage[f] = "ACKED" /\ ~(Elems(durable[f]) \subseteq Elems(memDb[f]))
               THEN {"DiffAbortAfterNewLeader"} ELSE {}))

MCFollowerExitToLooking(f) == FollowerExitToLooking(f) /\ UNCHANGED counters /\ NoMark

MCLeaderShutdown(l) == LeaderShutdown(l) /\ UNCHANGED counters /\ NoMark
MCEnterElectionPhase(s) == EnterElectionPhase(s) /\ UNCHANGED counters /\ NoMark

MCReload(s) == ReloadDatabase(s) /\ UNCHANGED counters /\ Mark({"ReloadAfterClear"})

-----------------------------------------------------------------------------

MCElectionNext ==
    \/ MCBeginElection
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s, c \in Server : MCFinishElection(s, c)
    \/ \E s \in Server : MCEnterDiscovery(s)
    \/ \E l \in Server : MCLeaderProposeEpoch(l)
    \/ \E f \in Server : MCPersistFollowerAccepted(f)
    \/ \E l, f \in Server : MCRecordEpochAck(l, f)
    \/ \E l \in Server : MCLeaderEpochQuorum(l)
    \/ \E l \in Server : MCLeaderStartSync(l)

MCSyncNext ==
    \/ \E f \in Server : MCEnterFollowerSync(f)
    \/ \E f \in Server : \E m \in {"DIFF", "TRUNC", "SNAP"} : MCChooseSync(f, m)
    \/ \E f \in Server : MCApplySnapshot(f)
    \/ \E f \in Server : MCTruncateLog(f)
    \/ \E f \in Server : \E t \in Txn : MCSyncPacket(f, t)
    \/ \E f \in Server : MCSyncCommit(f)
    \/ \E f \in Server : MCSyncSnapshot(f)
    \/ \E f \in Server : MCPersistFollowerCurrent(f)
    \/ \E f \in Server : MCNewLeaderModeNone(f)
    \/ \E f \in Server : MCAckNewLeader(f)
    \/ \E l \in Server : MCFormNewLeaderQuorum(l)
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ \E f \in Server : MCUpToDate(f)
    \/ \E f \in Server : MCCompleteSync(f)
    \/ \E f \in Server : MCFollowerBroadcast(f)

MCBroadcastNext ==
    \/ \E l \in Server : MCLeaderPropose(l)
    \/ \E f \in Server : \E t \in Txn : MCFollowerPending(f, t)
    \/ \E s \in Server : \E t \in Txn : MCQueue(s, t)
    \/ \E s \in Server : \E t \in Txn : MCFlush(s, t)
    \/ \E l, src \in Server : \E t \in Txn : MCAck(l, src, t)
    \/ \E l \in Server : \E t \in Txn : MCCommit(l, t)
    \/ \E f \in Server : \E t \in Txn : MCFollowerCommit(f, t)
    \/ \E s \in Server : \E t \in Txn : MCApply(s, t)

MCSnapshotNext ==
    \/ \E s \in Server : MCBeginSnapshot(s)
    \/ \E s \in Server : MCFinishSnapshot(s)

MCFaultNext ==
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)
    \/ \E f \in Server : MCLearnerShutdown(f)
    \/ \E f \in Server : MCFollowerExitToLooking(f)
    \/ \E l \in Server : MCLeaderShutdown(l)
    \/ \E s \in Server : MCEnterElectionPhase(s)
    \/ \E s \in Server : MCReload(s)

MCNext ==
    \/ MCElectionNext
    \/ MCSyncNext
    \/ MCBroadcastNext
    \/ MCSnapshotNext
    \/ MCFaultNext

MCSpec == MCInit /\ [][MCNext]_mcvars

Symmetry == Permutations(Server)

MCTypeOK ==
    /\ TypeOK
    /\ counters \in [rounds : Nat, crashes : Nat, exits : Nat, snapshots : Nat]
    /\ seen \subseteq {"FinishElection", "JoinEstablishedLeader", "ChooseDIFF",
                       "ChooseTRUNC", "ChooseSNAP", "ApplySnapshot",
                       "TruncateLog", "InMemorySyncCommitSNAP",
                       "InMemorySyncCommitTRUNC", "CompleteSync", "Commit",
                       "Restart", "SnapAbortBeforeNewLeader",
                       "TruncAbortWithMemoryOnlyCommit",
                       "DiffAbortAfterNewLeader", "ReloadAfterClear",
                       "FinishSnapshot"}

\* Reachability sentinels: a violation of `Never(x)` is a witness that x is
\* reachable under the checked configuration, not a safety failure.
NeverElection == "FinishElection" \notin seen
NeverCommit == "Commit" \notin seen
NeverApply == \A s \in Server : applied[s] = <<>>
NeverSnapshot == "FinishSnapshot" \notin seen
NeverRestart == "Restart" \notin seen
NeverJoinEstablishedLeader == "JoinEstablishedLeader" \notin seen
NeverChooseTrunc == "ChooseTRUNC" \notin seen
NeverDiffAbortAfterNewLeader == "DiffAbortAfterNewLeader" \notin seen
NeverCompleteSync == "CompleteSync" \notin seen
NeverSnapAbort == "SnapAbortBeforeNewLeader" \notin seen
NeverReloadAfterClear == "ReloadAfterClear" \notin seen
NeverTruncAbortMemoryOnly == "TruncAbortWithMemoryOnlyCommit" \notin seen
NeverInMemorySyncCommitSnap == "InMemorySyncCommitSNAP" \notin seen

=============================================================================
