------------------------------- MODULE MC -------------------------------
(* Model-checking wrapper for the updated reference.  Fault-like,         *)
(* nondeterministic environment steps are counter-bounded; reactive        *)
(* protocol steps are not.                                                 *)
EXTENDS base

B == INSTANCE base

CONSTANTS MaxCrash, MaxDrop, MaxSnapshot, MaxShutdown, MaxDepth
ASSUME /\ MaxCrash \in Nat /\ MaxDrop \in Nat /\ MaxSnapshot \in Nat
       /\ MaxShutdown \in Nat /\ MaxDepth \in Nat

VARIABLES counters, seen
mcVars == <<counters, seen>>

SeenNames == {"election", "leader", "sync", "DIFF", "TRUNC", "SNAP",
              "nlPersist", "nlStartup", "pendingLogged", "nlAck",
              "established", "broadcast", "uptodate", "mutation", "durable",
              "commit", "apply", "snapshot", "crash", "restart", "drop",
              "shutdown", "shutdownSkipped", "shutdownSkippedAfterAck",
              "postAckLogged", "syncCommitDelivered", "followerBroadcast"}

MCInit ==
    /\ Init
    /\ counters = [crash |-> 0, drop |-> 0, snapshot |-> 0, shutdown |-> 0]
    /\ seen = {}

Mark(names) == seen' = seen \cup names

MCBeginElection(s) == /\ B!BeginElection(s) /\ Mark({"election"}) /\ UNCHANGED counters
MCCastVote(v, c) == /\ B!CastVote(v, c) /\ UNCHANGED mcVars
MCWinElection(s) == /\ B!WinElection(s) /\ Mark({"leader"}) /\ UNCHANGED counters
MCFollowLeader(s, l) == /\ B!FollowLeader(s, l) /\ UNCHANGED mcVars
MCAcceptEpoch(s) == /\ B!AcceptEpoch(s) /\ UNCHANGED mcVars
MCFinishDiscovery(l) == /\ B!FinishDiscovery(l) /\ UNCHANGED mcVars
MCEnterSyncPhase(s, l) == /\ B!EnterSyncPhase(s, l) /\ UNCHANGED mcVars
MCSyncWithLeader(s, mode) ==
    /\ B!SyncWithLeader(s, mode)
    /\ Mark({"sync", mode})
    /\ UNCHANGED counters
MCLearnerNewLeaderPersist(s) ==
    /\ B!LearnerNewLeaderPersist(s) /\ Mark({"nlPersist"}) /\ UNCHANGED counters
MCLearnerNewLeaderStartup(s) ==
    /\ B!LearnerNewLeaderStartup(s) /\ Mark({"nlStartup"}) /\ UNCHANGED counters
MCLearnerLogPendingOne(s) ==
    /\ B!LearnerLogPendingOne(s) /\ Mark({"pendingLogged"}) /\ UNCHANGED counters
MCLearnerSendNewLeaderAck(s) ==
    /\ B!LearnerSendNewLeaderAck(s) /\ Mark({"nlAck"}) /\ UNCHANGED counters
MCLeaderStartZkServer(l) ==
    /\ B!LeaderStartZkServer(l) /\ Mark({"established"}) /\ UNCHANGED counters
MCLeaderEnterBroadcast(l) ==
    /\ B!LeaderEnterBroadcast(l) /\ Mark({"broadcast"}) /\ UNCHANGED counters
MCLearnerUptodateStartServing(s) ==
    /\ B!LearnerUptodateStartServing(s) /\ Mark({"uptodate"}) /\ UNCHANGED counters
MCLearnerUptodateLogOne(s) ==
    /\ B!LearnerUptodateLogOne(s) /\ Mark({"postAckLogged"}) /\ UNCHANGED counters
MCLearnerUptodateCommitOne(s) ==
    /\ B!LearnerUptodateCommitOne(s) /\ Mark({"syncCommitDelivered"}) /\ UNCHANGED counters
MCLearnerEnterBroadcast(s) ==
    /\ B!LearnerEnterBroadcast(s) /\ Mark({"followerBroadcast"}) /\ UNCHANGED counters
MCPropose(l, t) == /\ B!Propose(l, t) /\ Mark({"mutation"}) /\ UNCHANGED counters
MCReceiveProposal(m) == /\ B!ReceiveProposal(m) /\ UNCHANGED mcVars
MCAppendOne(s) == /\ B!AppendOne(s) /\ UNCHANGED mcVars
MCFsyncOne(s) == /\ B!FsyncOne(s) /\ Mark({"durable"}) /\ UNCHANGED counters
MCDeliverAck(m) == /\ B!DeliverAck(m) /\ UNCHANGED mcVars
MCCommit(l, t) == /\ B!Commit(l, t) /\ Mark({"commit"}) /\ UNCHANGED counters
MCReceiveCommit(m) == /\ B!ReceiveCommit(m) /\ UNCHANGED mcVars
MCApplyOne(s) == /\ B!ApplyOne(s) /\ Mark({"apply"}) /\ UNCHANGED counters
MCTakeSnapshot(s) ==
    /\ counters.snapshot < MaxSnapshot
    /\ B!TakeSnapshot(s)
    /\ counters' = [counters EXCEPT !.snapshot = @ + 1]
    /\ Mark({"snapshot"})
MCServerShutdown(s) ==
    /\ counters.shutdown < MaxShutdown
    /\ B!ServerShutdown(s)
    /\ counters' = [counters EXCEPT !.shutdown = @ + 1]
    /\ Mark({"shutdown"}
            \cup (IF zkState[s] = "INITIAL" THEN {"shutdownSkipped"} ELSE {})
            \cup (IF learnerStep[s] = "acked" THEN {"shutdownSkippedAfterAck"}
                  ELSE {}))
MCCrash(s) ==
    /\ counters.crash < MaxCrash
    /\ B!Crash(s)
    /\ counters' = [counters EXCEPT !.crash = @ + 1]
    /\ Mark({"crash"})
MCRestart(s) == /\ B!Restart(s) /\ Mark({"restart"}) /\ UNCHANGED counters
MCDropMessage(m) ==
    /\ counters.drop < MaxDrop
    /\ B!DropMessage(m)
    /\ counters' = [counters EXCEPT !.drop = @ + 1]
    /\ Mark({"drop"})

MCNext ==
    \/ \E s \in Server : MCBeginElection(s)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s \in Server : MCWinElection(s)
    \/ \E s, l \in Server : MCFollowLeader(s, l)
    \/ \E s \in Server : MCAcceptEpoch(s)
    \/ \E l \in Server : MCFinishDiscovery(l)
    \/ \E s, l \in Server : MCEnterSyncPhase(s, l)
    \/ \E s \in Server, mode \in SyncModes \ {"NONE"} : MCSyncWithLeader(s, mode)
    \/ \E s \in Server : MCLearnerNewLeaderPersist(s)
    \/ \E s \in Server : MCLearnerNewLeaderStartup(s)
    \/ \E s \in Server : MCLearnerLogPendingOne(s)
    \/ \E s \in Server : MCLearnerSendNewLeaderAck(s)
    \/ \E l \in Server : MCLeaderStartZkServer(l)
    \/ \E l \in Server : MCLeaderEnterBroadcast(l)
    \/ \E s \in Server : MCLearnerUptodateStartServing(s)
    \/ \E s \in Server : MCLearnerUptodateLogOne(s)
    \/ \E s \in Server : MCLearnerUptodateCommitOne(s)
    \/ \E s \in Server : MCLearnerEnterBroadcast(s)
    \/ \E l \in Server, t \in Txn : MCPropose(l, t)
    \/ \E m \in messages : MCReceiveProposal(m)
    \/ \E s \in Server : MCAppendOne(s)
    \/ \E s \in Server : MCFsyncOne(s)
    \/ \E m \in messages : MCDeliverAck(m)
    \/ \E l \in Server, t \in Txn : MCCommit(l, t)
    \/ \E m \in messages : MCReceiveCommit(m)
    \/ \E s \in Server : MCApplyOne(s)
    \/ \E s \in Server : MCTakeSnapshot(s)
    \/ \E s \in Server : MCServerShutdown(s)
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)
    \/ \E m \in messages : MCDropMessage(m)

MCSpec == MCInit /\ [][MCNext]_<<allVars, mcVars>>

MCTypeOK == /\ counters \in [crash : 0..MaxCrash, drop : 0..MaxDrop,
                              snapshot : 0..MaxSnapshot,
                              shutdown : 0..MaxShutdown]
            /\ seen \subseteq SeenNames

\* Explicit BFS level bound (0 disables).  A depth-bounded run is
\* budget-limited coverage, never an exhaustive proof.
DepthBound == MaxDepth = 0 \/ TLCGet("level") <= MaxDepth

\* Reachability canaries (expected to be violated).
NotElectionReached == "leader" \notin seen
NotMutationReached == "apply" \notin seen
NotRecoveryReached == ~({"crash", "restart"} \subseteq seen)
NotSyncReached == "sync" \notin seen
NotNewLeaderAckReached == "nlAck" \notin seen
NotPendingLoggedAndAcked == ~({"pendingLogged", "nlAck", "established"} \subseteq seen)
NotUptodateReached == "uptodate" \notin seen
NotShutdownSkippedAfterAck == "shutdownSkippedAfterAck" \notin seen

=============================================================================
