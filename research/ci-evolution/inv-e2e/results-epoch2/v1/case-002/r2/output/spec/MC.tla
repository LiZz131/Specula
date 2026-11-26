------------------------------- MODULE MC -------------------------------
EXTENDS base

B == INSTANCE base

CONSTANTS MaxCrash, MaxDrop, MaxSnapshot
ASSUME /\ MaxCrash \in Nat /\ MaxDrop \in Nat /\ MaxSnapshot \in Nat

VARIABLES counters, seen
mcVars == <<counters, seen>>

MCInit ==
    /\ Init
    /\ counters = [crash |-> 0, drop |-> 0, snapshot |-> 0]
    /\ seen = {}

Mark(name) == seen' = seen \cup {name}

MCBeginElection(s) == /\ B!BeginElection(s) /\ Mark("election") /\ UNCHANGED counters
MCCastVote(v, c) == /\ B!CastVote(v, c) /\ UNCHANGED mcVars
MCWinElection(s) == /\ B!WinElection(s) /\ Mark("leader") /\ UNCHANGED counters
MCFollowLeader(s, l) == /\ B!FollowLeader(s, l) /\ UNCHANGED mcVars
MCAcceptEpoch(s) == /\ B!AcceptEpoch(s) /\ UNCHANGED mcVars
MCFinishDiscovery(l) == /\ B!FinishDiscovery(l) /\ UNCHANGED mcVars
MCEnterSyncPhase(s, l) == /\ B!EnterSyncPhase(s, l) /\ UNCHANGED mcVars
MCSelectSync(s, l, mode) ==
    /\ B!SelectSync(s, l, mode)
    /\ seen' = seen \cup {"sync", mode}
    /\ UNCHANGED counters
\* UPDATE-MAP code: Learner.java:726-760 update: Update!AffectedActions
MCLearnerNewLeader(s) == /\ B!LearnerNewLeader(s) /\ Mark("newleader") /\ UNCHANGED counters
MCLearnerAckNewLeader(s) == /\ B!LearnerAckNewLeader(s) /\ Mark("nlack") /\ UNCHANGED counters
MCEnterBroadcast(s) == /\ B!EnterBroadcast(s) /\ Mark("uptodate") /\ UNCHANGED counters
MCLeaderBroadcast(l) == /\ B!LeaderBroadcast(l) /\ Mark("broadcast") /\ UNCHANGED counters
MCPropose(l, t) == /\ B!Propose(l, t) /\ Mark("mutation") /\ UNCHANGED counters
MCReceiveProposal(m) == /\ B!ReceiveProposal(m) /\ UNCHANGED mcVars
MCObserveCommit(s, t, ep) == /\ B!ObserveCommit(s, t, ep) /\ UNCHANGED mcVars
MCAppendOne(s) == /\ B!AppendOne(s) /\ UNCHANGED mcVars
MCFsyncOne(s) == /\ B!FsyncOne(s) /\ Mark("durable") /\ UNCHANGED counters
MCDeliverAck(m) == /\ B!DeliverAck(m) /\ UNCHANGED mcVars
MCCommit(l, t) == /\ B!Commit(l, t) /\ Mark("commit") /\ UNCHANGED counters
MCReceiveCommit(m) == /\ B!ReceiveCommit(m) /\ UNCHANGED mcVars
MCApplyOne(s) == /\ B!ApplyOne(s) /\ Mark("apply") /\ UNCHANGED counters
MCTakeSnapshot(s) ==
    /\ counters.snapshot < MaxSnapshot
    /\ B!TakeSnapshot(s)
    /\ counters' = [counters EXCEPT !.snapshot = @ + 1]
    /\ Mark("snapshot")
MCCrash(s) ==
    /\ counters.crash < MaxCrash
    /\ B!Crash(s)
    /\ counters' = [counters EXCEPT !.crash = @ + 1]
    /\ Mark("crash")
MCRestart(s) == /\ B!Restart(s) /\ Mark("restart") /\ UNCHANGED counters
MCDropMessage(m) ==
    /\ counters.drop < MaxDrop
    /\ B!DropMessage(m)
    /\ counters' = [counters EXCEPT !.drop = @ + 1]
    /\ Mark("drop")

MCNext ==
    \/ \E s \in Server : MCBeginElection(s)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s \in Server : MCWinElection(s)
    \/ \E s, l \in Server : MCFollowLeader(s, l)
    \/ \E s \in Server : MCAcceptEpoch(s)
    \/ \E l \in Server : MCFinishDiscovery(l)
    \/ \E s, l \in Server : MCEnterSyncPhase(s, l)
    \/ \E s, l \in Server, mode \in SyncModes \ {"NONE"} : MCSelectSync(s, l, mode)
    \/ \E s \in Server : MCLearnerNewLeader(s)
    \/ \E s \in Server : MCLearnerAckNewLeader(s)
    \/ \E s \in Server : MCEnterBroadcast(s)
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ \E l \in Server, t \in Txn : MCPropose(l, t)
    \/ \E m \in messages : MCReceiveProposal(m)
    \/ \E s \in Server, t \in Txn, ep \in Epoch : MCObserveCommit(s, t, ep)
    \/ \E s \in Server : MCAppendOne(s)
    \/ \E s \in Server : MCFsyncOne(s)
    \/ \E m \in messages : MCDeliverAck(m)
    \/ \E l \in Server, t \in Txn : MCCommit(l, t)
    \/ \E m \in messages : MCReceiveCommit(m)
    \/ \E s \in Server : MCApplyOne(s)
    \/ \E s \in Server : MCTakeSnapshot(s)
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)
    \/ \E m \in messages : MCDropMessage(m)

MCSpec == MCInit /\ [][MCNext]_<<allVars, mcVars>>

SeenNames == {"election", "leader", "sync", "DIFF", "TRUNC", "SNAP",
              "newleader", "nlack", "uptodate", "broadcast", "mutation",
              "durable", "commit", "apply", "snapshot", "crash", "restart",
              "drop"}

MCTypeOK == /\ counters \in [crash : 0..MaxCrash,
                              drop : 0..MaxDrop,
                              snapshot : 0..MaxSnapshot]
            /\ seen \subseteq SeenNames

\* Reachability canaries (negated goals; an expected violation is a witness).
NotElectionReached == "leader" \notin seen
NotMutationReached == "apply" \notin seen
NotRecoveryReached == ~({"crash", "restart"} \subseteq seen)
NotSyncReached == "sync" \notin seen
\* Update canaries: every changed learner step and its leader-side consumer.
NotNewLeaderAckReached == ~({"newleader", "nlack", "uptodate", "broadcast"} \subseteq seen)
NotDiffHandoffReached ==
    ~(\E s \in Server : /\ learnerStage[s] = "acked"
                        /\ syncMode[s] = "NONE"
                        /\ Len(proposed[s]) > Len(durable[s]))

=============================================================================
