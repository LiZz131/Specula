------------------------------- MODULE MC -------------------------------
EXTENDS base

CONSTANTS TrackCoverage, MaxRounds, MaxCrashes, MaxExits, MaxSnapshots

(***************************************************************************)
(* Finite exploration driver. Bounds limit executions; they are not proof. *)
(* Fault injections are counted: election rounds, crashes, learner exits   *)
(* injected by I/O failure, and periodic snapshots.  Reactive protocol      *)
(* steps (sync, pipeline, restart, reload, exit after leader loss) are not. *)
(***************************************************************************)

VARIABLES counters, seen

mcvars == <<vars, counters, seen>>

MCInit ==
    /\ Init
    /\ counters = [rounds |-> 1, crashes |-> 0, exits |-> 0, snapshots |-> 0]
    /\ seen = {"Init"}

CoverageEvents == TransitionNames \cup {
    "LearnerExitSnapUnpersisted", "LearnerExitTruncUnpersisted",
    "LearnerExitServing", "ReloadAfterSnapExit", "DiffAfterReload",
    "LeakedFlushAfterResync", "DiffWithUnbackedBaseline"
}

Mark(name) ==
    seen' = IF TrackCoverage /\ name \in CoverageEvents
            THEN seen \cup {name}
            ELSE seen

Mark2(a, b, cond) ==
    seen' = IF TrackCoverage
            THEN seen \cup {a} \cup (IF cond THEN {b} ELSE {})
            ELSE seen

\* Helper: the in-memory baseline is not covered by the log (durable or a
\* pending/leaked log write).
Unbacked(s) ==
    ~(Elems(prepared[s]) \subseteq Elems(durable[s]) \cup Elems(syncQueued[s]) \cup LeakedElems(s))

MCBeginElection(c) ==
    /\ counters.rounds < MaxRounds
    /\ BeginElectionRound(c)
    /\ counters' = [counters EXCEPT !.rounds = @ + 1]
    /\ Mark("BeginElectionRound")

MCCastVote(v, c) ==
    /\ CastVote(v, c)
    /\ UNCHANGED counters
    /\ Mark("CastVote")

MCFinishElection(s, c) ==
    /\ FinishElection(s, c)
    /\ UNCHANGED counters
    /\ Mark("FinishElection")

MCEnterDiscovery(s) ==
    /\ running[s] /\ phase[s] = "ELECTION"
    /\ role[s] \in {"LEADING", "FOLLOWING"}
    /\ ObserveSetZabState(s, "DISCOVERY")
    /\ UNCHANGED counters
    /\ Mark("SetZabState")

MCPersistLeaderAccepted(l) ==
    /\ role[l] = "LEADING" /\ phase[l] = "DISCOVERY"
    /\ currentEpoch[l] < MaxEpoch
    /\ PersistAcceptedEpoch(l, currentEpoch[l] + 1)
    /\ UNCHANGED counters
    /\ Mark("PersistAcceptedEpoch")

\* Learner.registerWithLeader persists a strictly newer accepted epoch only
\* (Learner.java:497-512); an equal epoch is re-acked without a write.
MCPersistFollowerAccepted(f) ==
    /\ role[f] = "FOLLOWING" /\ phase[f] = "DISCOVERY"
    /\ leaderOf[f] \in Server
    /\ epochProposal[leaderOf[f]] > acceptedEpoch[f]
    /\ PersistAcceptedEpoch(f, epochProposal[leaderOf[f]])
    /\ UNCHANGED counters
    /\ Mark("PersistAcceptedEpoch")

MCRecordEpochAck(l, f) ==
    /\ RecordEpochAck(l, f)
    /\ UNCHANGED counters
    /\ Mark("RecordEpochAck")

MCFormEpochQuorum(l) ==
    /\ FormEpochQuorum(l)
    /\ UNCHANGED counters
    /\ Mark("FormEpochQuorum")

\* A learner enters SYNCHRONIZATION after LEADERINFO/ACKEPOCH; the leader's
\* LearnerHandler syncs only after the epoch-ack quorum, and also serves a
\* late joiner while the leader is in BROADCAST (Follower.java:105-111;
\* LearnerHandler.java:500-560).
MCEnterFollowerSync(f) ==
    /\ role[f] = "FOLLOWING" /\ phase[f] = "DISCOVERY"
    /\ leaderOf[f] \in Server
    /\ running[leaderOf[f]] /\ role[leaderOf[f]] = "LEADING"
    /\ phase[leaderOf[f]] \in {"SYNCHRONIZATION", "BROADCAST"}
    /\ acceptedEpoch[f] = acceptedEpoch[leaderOf[f]]
    /\ ObserveSetZabState(f, "SYNCHRONIZATION")
    /\ UNCHANGED counters
    /\ Mark("SetZabState")

MCChooseSync(f, m) ==
    /\ phase[f] = "SYNCHRONIZATION"
    /\ ChooseSyncMode(f, m)
    /\ UNCHANGED counters
    /\ Mark2("ChooseSyncMode", "DiffWithUnbackedBaseline", m = "DIFF" /\ Unbacked(f))

MCLoadSyncSnapshot(f) ==
    /\ LoadSyncSnapshot(f)
    /\ UNCHANGED counters
    /\ Mark("LoadSyncSnapshot")

MCTruncateLog(f) ==
    /\ TruncateLog(f)
    /\ UNCHANGED counters
    /\ Mark("TruncateLog")

MCApplySyncCommit(f, t) ==
    /\ ApplySyncCommit(f, t)
    /\ UNCHANGED counters
    /\ Mark("ApplySyncCommit")

\* NEWLEADER snapshot of a SNAP/TRUNC image (Learner.java:739-741).
MCBeginSyncSnapshot(f) ==
    /\ learnerStage[f] = "DATA" /\ syncMode[f] \in {"SNAP", "TRUNC"}
    /\ role[f] = "FOLLOWING"
    /\ BeginSnapshot(f)
    /\ UNCHANGED counters
    /\ Mark("BeginSnapshot")

MCFinishSyncSnapshot(f) ==
    /\ FinishSyncSnapshot(f)
    /\ UNCHANGED counters
    /\ Mark("FinishSyncSnapshot")

\* setCurrentEpoch at NEWLEADER, after the sync snapshot (Learner.java:743).
MCPersistFollowerCurrent(f) ==
    /\ role[f] = "FOLLOWING" /\ phase[f] = "SYNCHRONIZATION"
    /\ \/ learnerStage[f] = "DATA" /\ syncMode[f] = "DIFF"
       \/ learnerStage[f] = "SNAPPED"
    /\ acceptedEpoch[f] > currentEpoch[f]
    /\ PersistCurrentEpoch(f, acceptedEpoch[f])
    /\ UNCHANGED counters
    /\ Mark("PersistCurrentEpoch")

MCLearnerNewLeader(f) ==
    /\ LearnerNewLeader(f)
    /\ UNCHANGED counters
    /\ Mark("LearnerNewLeader")

MCFormNewLeaderQuorum(l) ==
    /\ ~newLeaderReady[l]
    /\ FormNewLeaderQuorum(l)
    /\ UNCHANGED counters
    /\ Mark("FormNewLeaderQuorum")

MCCompleteSync(f) ==
    /\ leaderOf[f] \in Server
    /\ CompleteLearnerSync(f, leaderOf[f])
    /\ UNCHANGED counters
    /\ Mark("CompleteLearnerSync")

MCLeaderBroadcast(l) ==
    /\ role[l] = "LEADING" /\ phase[l] = "SYNCHRONIZATION"
    /\ newLeaderReady[l]
    /\ ObserveSetZabState(l, "BROADCAST")
    /\ UNCHANGED counters
    /\ Mark("SetZabState")

MCFollowerBroadcast(f) ==
    /\ role[f] = "FOLLOWING" /\ phase[f] = "SYNCHRONIZATION"
    /\ syncComplete[f]
    /\ ObserveSetZabState(f, "BROADCAST")
    /\ UNCHANGED counters
    /\ Mark("SetZabState")

MCLeaderPropose(l) ==
    /\ nextTxn \in Txn
    /\ LeaderProposeAndLog(l, nextTxn)
    /\ UNCHANGED counters
    /\ Mark("LeaderPropose")

MCFollowerLog(f, t) ==
    /\ FollowerLogRequest(f, t)
    /\ UNCHANGED counters
    /\ Mark("FollowerPendingProposal")

MCFlush(s, t) ==
    /\ FlushTxnLog(s, t)
    /\ UNCHANGED counters
    /\ Mark("FlushTxnLog")

MCFlushLeaked(s, i, t) ==
    /\ FlushLeakedTxnLog(s, i, t)
    /\ UNCHANGED counters
    /\ Mark2("FlushLeakedTxnLog", "LeakedFlushAfterResync",
             learnerStage[s] /= "NONE" \/ role[s] = "LEADING")

MCAck(l, source, t) ==
    /\ RecordProposalAck(l, source, t)
    /\ UNCHANGED counters
    /\ Mark("RecordProposalAck")

MCCommit(l, t) ==
    /\ CommitProposal(l, t)
    /\ UNCHANGED counters
    /\ Mark("CommitProposal")

MCFollowerCommit(f, t) ==
    /\ FollowerCommit(f, t)
    /\ UNCHANGED counters
    /\ Mark("FollowerCommit")

MCApply(s, t) ==
    /\ ApplyTxn(s, t)
    /\ UNCHANGED counters
    /\ Mark("ApplyTxn")

MCBeginSnapshot(s) ==
    /\ counters.snapshots < MaxSnapshots
    /\ phase[s] = "BROADCAST"
    /\ BeginSnapshot(s)
    /\ counters' = [counters EXCEPT !.snapshots = @ + 1]
    /\ Mark("BeginSnapshot")

MCFinishSnapshot(s) ==
    /\ FinishSnapshot(s)
    /\ UNCHANGED counters
    /\ Mark("FinishSnapshot")

MCCrash(s) ==
    /\ counters.crashes < MaxCrashes
    /\ (phase[s] = "BROADCAST" \/ snapshotBusy[s])
    /\ Crash(s)
    /\ counters' = [counters EXCEPT !.crashes = @ + 1]
    /\ Mark("Crash")

MCRestart(s) ==
    /\ ~running[s]
    /\ RestartLoadDatabase(s, acceptedEpoch[s], currentEpoch[s])
    /\ UNCHANGED counters
    /\ Mark("RestartLoadDatabase")

ExitMarks(f) ==
    { n \in {"LearnerExitSnapUnpersisted", "LearnerExitTruncUnpersisted",
             "LearnerExitServing"} :
        \/ n = "LearnerExitSnapUnpersisted"
           /\ syncMode[f] = "SNAP" /\ learnerStage[f] = "DATA" /\ Unbacked(f)
        \/ n = "LearnerExitTruncUnpersisted"
           /\ syncMode[f] = "TRUNC" /\ learnerStage[f] = "DATA" /\ Unbacked(f)
        \/ n = "LearnerExitServing" /\ ZkServing(f) }

\* Learner exit injected by an I/O failure or timeout while following
\* (Follower.java:130-135 -> QuorumPeer.java:1475-1479).  Counted fault.
MCLearnerExit(f) ==
    /\ counters.exits < MaxExits
    /\ LearnerExit(f)
    /\ counters' = [counters EXCEPT !.exits = @ + 1]
    /\ seen' = IF TrackCoverage THEN seen \cup {"LearnerExit"} \cup ExitMarks(f) ELSE seen

\* Learner exit because the leader is gone (reactive, not counted).
MCLearnerExitLeaderGone(f) ==
    /\ leaderOf[f] \in Server /\ ~running[leaderOf[f]]
    /\ LearnerExit(f)
    /\ UNCHANGED counters
    /\ seen' = IF TrackCoverage THEN seen \cup {"LearnerExit"} \cup ExitMarks(f) ELSE seen

MCReloadDatabase(s) ==
    /\ ReloadDatabase(s)
    /\ UNCHANGED counters
    /\ Mark2("ReloadDatabase", "ReloadAfterSnapExit", syncMode[s] = "SNAP")

MCNext ==
    \/ \E c \in Server : MCBeginElection(c)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s, c \in Server : MCFinishElection(s, c)
    \/ \E s \in Server : MCEnterDiscovery(s)
    \/ \E l \in Server : MCPersistLeaderAccepted(l)
    \/ \E f \in Server : MCPersistFollowerAccepted(f)
    \/ \E l, f \in Server : MCRecordEpochAck(l, f)
    \/ \E l \in Server : MCFormEpochQuorum(l)
    \/ \E f \in Server : MCEnterFollowerSync(f)
    \/ \E f \in Server : \E m \in {"DIFF", "TRUNC", "SNAP"} : MCChooseSync(f, m)
    \/ \E f \in Server : MCLoadSyncSnapshot(f)
    \/ \E f \in Server : MCTruncateLog(f)
    \/ \E f \in Server : \E t \in Txn : MCApplySyncCommit(f, t)
    \/ \E f \in Server : MCBeginSyncSnapshot(f)
    \/ \E f \in Server : MCFinishSyncSnapshot(f)
    \/ \E f \in Server : MCPersistFollowerCurrent(f)
    \/ \E f \in Server : MCLearnerNewLeader(f)
    \/ \E l \in Server : MCFormNewLeaderQuorum(l)
    \/ \E f \in Server : MCCompleteSync(f)
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ \E f \in Server : MCFollowerBroadcast(f)
    \/ \E l \in Server : MCLeaderPropose(l)
    \/ \E f \in Server : \E t \in Txn : MCFollowerLog(f, t)
    \/ \E s \in Server : \E t \in Txn : MCFlush(s, t)
    \/ \E s \in Server : \E i \in 1..Len(leakedQueued[s]) : \E t \in Txn : MCFlushLeaked(s, i, t)
    \/ \E l, source \in Server : \E t \in Txn : MCAck(l, source, t)
    \/ \E l \in Server : \E t \in Txn : MCCommit(l, t)
    \/ \E f \in Server : \E t \in Txn : MCFollowerCommit(f, t)
    \/ \E s \in Server : \E t \in Txn : MCApply(s, t)
    \/ \E s \in Server : MCBeginSnapshot(s)
    \/ \E s \in Server : MCFinishSnapshot(s)
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)
    \/ \E f \in Server : MCLearnerExit(f)
    \/ \E f \in Server : MCLearnerExitLeaderGone(f)
    \/ \E s \in Server : MCReloadDatabase(s)

(***************************************************************************)
(* Standard convergence projection: all ordinary protocol actions without  *)
(* counted fault injections (as in the prior MC.cfg).                       *)
(***************************************************************************)
MCCoreNext == MCNext /\ UNCHANGED counters

MCTypeOK ==
    /\ TypeOK
    /\ counters \in [rounds : Nat, crashes : Nat, exits : Nat, snapshots : Nat]
    /\ seen \subseteq CoverageEvents \cup {"Init"}

(***************************************************************************)
(* Steady state after the first election: one leader and two synced        *)
(* followers in BROADCAST at epoch 1, no transactions.  Used only as the   *)
(* Init of focused update checks; its reachability from MCInit is checked  *)
(* by MC-steady-canary.cfg (SteadyStateUnreachable).                       *)
(***************************************************************************)
SteadyLeader == CHOOSE s \in Server : TRUE
SteadyState(L) ==
    /\ running = [s \in Server |-> TRUE]
    /\ role = [s \in Server |-> IF s = L THEN "LEADING" ELSE "FOLLOWING"]
    /\ phase = [s \in Server |-> "BROADCAST"]
    /\ syncMode = [s \in Server |-> "NONE"]
    /\ leaderOf = [s \in Server |-> L]
    /\ acceptedEpoch = [s \in Server |-> 1]
    /\ currentEpoch = [s \in Server |-> 1]
    /\ epochProposal = [s \in Server |-> 1]
    /\ electionRound = 0
    /\ votedFor = [s \in Server |-> L]
    /\ electionVotes = [s \in Server |-> IF s = L THEN Server ELSE {}]
    /\ epochAcks = [s \in Server |-> IF s = L THEN Server ELSE {}]
    /\ newLeaderAcks = [s \in Server |-> IF s = L THEN Server ELSE {}]
    /\ newLeaderReady = [s \in Server |-> s = L]
    /\ syncComplete = [s \in Server |-> s /= L]
    /\ learnerStage = [s \in Server |-> IF s = L THEN "NONE" ELSE "UPTODATE"]
    /\ dbCleared = [s \in Server |-> FALSE]
    /\ prepared = [s \in Server |-> <<>>]
    /\ syncQueued = [s \in Server |-> <<>>]
    /\ leakedQueued = [s \in Server |-> <<>>]
    /\ pending = [s \in Server |-> <<>>]
    /\ durable = [s \in Server |-> <<>>]
    /\ recoveryVisible = [s \in Server |-> <<>>]
    /\ committed = [s \in Server |-> <<>>]
    /\ applied = [s \in Server |-> <<>>]
    /\ globalCommitted = <<>>
    /\ acks = [t \in Txn |-> {}]
    /\ durabilityEvidence = [t \in Txn |-> {}]
    /\ commitWitness = [t \in Txn |-> {}]
    /\ nextTxn = 1
    /\ snapshotBusy = [s \in Server |-> FALSE]
    /\ snapshotImage = [s \in Server |-> <<>>]
    /\ snapshotPublished = [s \in Server |-> <<>>]

SteadyInit ==
    /\ SteadyState(SteadyLeader)
    /\ counters = [rounds |-> 1, crashes |-> 0, exits |-> 0, snapshots |-> 0]
    /\ seen = {"Init"}

SteadyStateUnreachable == ~\E L \in Server : SteadyState(L)

\* Coverage sentinels (expected violations are reachability witnesses).
ReachedElection == "FinishElection" \in seen
ReachedEpochQuorum == "FormEpochQuorum" \in seen
ReachedSnapshot == "FinishSnapshot" \in seen \/ "FinishSyncSnapshot" \in seen
ElectionUnreachable == ~ReachedElection
SnapshotUnreachable == ~ReachedSnapshot
ReachedSync == "CompleteLearnerSync" \in seen
ReachedCommit == \E t \in Txn : Quorum(commitWitness[t])
ReachedApply == \E s \in Server : Len(applied[s]) > 0
ReachedRecovery == "RestartLoadDatabase" \in seen
SyncUnreachable == ~ReachedSync
CommitUnreachable == ~ReachedCommit
ApplyUnreachable == ~ReachedApply
RecoveryUnreachable == ~ReachedRecovery

(***************************************************************************)
(* Inherited canonical hunt schedules (prior MC.tla), rebased onto the      *)
(* refined sync/pipeline wrappers.  They call the same MC wrappers as      *)
(* MCNext and only remove unrelated choices.                               *)
(***************************************************************************)
WitnessLeader == CHOOSE s \in Server : TRUE
WitnessFollower == CHOOSE s \in Server \ {WitnessLeader} : TRUE

CommitHuntNext ==
    \/ \E v \in Server : MCCastVote(v, WitnessLeader)
    \/ MCFinishElection(WitnessLeader, WitnessLeader)
    \/ MCFinishElection(WitnessFollower, WitnessLeader)
    \/ MCEnterDiscovery(WitnessLeader)
    \/ MCEnterDiscovery(WitnessFollower)
    \/ MCPersistLeaderAccepted(WitnessLeader)
    \/ MCPersistFollowerAccepted(WitnessFollower)
    \/ MCRecordEpochAck(WitnessLeader, WitnessLeader)
    \/ MCRecordEpochAck(WitnessLeader, WitnessFollower)
    \/ MCFormEpochQuorum(WitnessLeader)
    \/ MCEnterFollowerSync(WitnessFollower)
    \/ MCChooseSync(WitnessFollower, "DIFF")
    \/ MCPersistFollowerCurrent(WitnessFollower)
    \/ MCLearnerNewLeader(WitnessFollower)
    \/ MCFormNewLeaderQuorum(WitnessLeader)
    \/ MCCompleteSync(WitnessFollower)
    \/ MCLeaderBroadcast(WitnessLeader)
    \/ MCFollowerBroadcast(WitnessFollower)
    \/ MCLeaderPropose(WitnessLeader)
    \/ \E t \in Txn : MCFollowerLog(WitnessFollower, t)
    \/ \E t \in Txn : MCFlush(WitnessLeader, t)
    \/ \E t \in Txn : MCFlush(WitnessFollower, t)
    \/ \E t \in Txn : MCAck(WitnessLeader, WitnessLeader, t)
    \/ \E t \in Txn : MCAck(WitnessLeader, WitnessFollower, t)
    \/ \E t \in Txn : MCCommit(WitnessLeader, t)

ApplyHuntNext ==
    \/ CommitHuntNext
    \/ \E t \in Txn : MCApply(WitnessLeader, t)

SnapshotHuntNext ==
    \/ ApplyHuntNext
    \/ MCBeginSnapshot(WitnessLeader)
    \/ MCFinishSnapshot(WitnessLeader)
    \/ MCBeginSnapshot(WitnessFollower)
    \/ MCFinishSnapshot(WitnessFollower)

RecoveryHuntNext ==
    \/ CommitHuntNext
    \/ \E t \in Txn : MCFollowerCommit(WitnessFollower, t)
    \/ \E t \in Txn : MCApply(WitnessLeader, t)
    \/ \E t \in Txn : MCApply(WitnessFollower, t)
    \/ MCCrash(WitnessLeader)
    \/ MCCrash(WitnessFollower)
    \/ MCRestart(WitnessLeader)
    \/ MCRestart(WitnessFollower)
    \/ MCLearnerExitLeaderGone(WitnessFollower)
    \/ MCBeginElection(WitnessLeader)

Symmetry == Permutations(Server)

=============================================================================
