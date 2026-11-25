------------------------------- MODULE MC -------------------------------
EXTENDS base

B == INSTANCE base

CONSTANTS MaxCrash, MaxDrop, MaxSnapshot
ASSUME /\ MaxCrash \in Nat /\ MaxDrop \in Nat /\ MaxSnapshot \in Nat

VARIABLES counters, seen
mcVars == <<counters, seen>>
vars == <<allVars, mcVars>>

MCInit ==
    /\ Init
    /\ counters = [crash |-> 0, drop |-> 0, snapshot |-> 0]
    /\ seen = {}

Mark(name) == seen' = seen \cup {name}
MarkAll(names) == seen' = seen \cup names

MCBeginElection(s) ==
    /\ B!BeginElection(s)
    /\ MarkAll({"election"} \cup
               (IF zkState[s] = "INITIAL" THEN {"initial-exit"} ELSE {}) \cup
               (IF zkState[s] = "INITIAL" /\ durable'[s] /= durable[s]
                THEN {"initial-exit-flushed"} ELSE {}))
    /\ UNCHANGED counters
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
MCFollowerProcessNewLeader(s) ==
    /\ B!FollowerProcessNewLeader(s)
    /\ MarkAll({"newleader-logged"} \cup
               (IF queued'[s] /= durable'[s] THEN {"newleader-nondurable"} ELSE {}))
    /\ UNCHANGED counters
MCFollowerSendNewLeaderAck(s) ==
    /\ B!FollowerSendNewLeaderAck(s)
    /\ MarkAll({"newleader-ack"} \cup
               (IF queued[s] /= durable[s] THEN {"newleader-ack-nondurable"} ELSE {}))
    /\ UNCHANGED counters
MCLeaderProcessNewLeaderAck(m) ==
    /\ B!LeaderProcessNewLeaderAck(m)
    /\ MarkAll(IF ackShadowed[m.from] THEN {"newleader-ack-rejected"} ELSE {"newleader-ack-counted"})
    /\ UNCHANGED counters
MCLeaderBroadcast(l) == /\ B!LeaderBroadcast(l) /\ Mark("broadcast") /\ UNCHANGED counters
MCFollowerProcessUpToDate(s) == /\ B!FollowerProcessUpToDate(s) /\ Mark("uptodate") /\ UNCHANGED counters
MCPropose(l, t) == /\ B!Propose(l, t) /\ Mark("mutation") /\ UNCHANGED counters
MCReceiveProposal(m) == /\ B!ReceiveProposal(m) /\ UNCHANGED mcVars
MCAppendOne(s) == /\ B!AppendOne(s) /\ UNCHANGED mcVars
MCFsyncOne(s) ==
    /\ B!FsyncOne(s)
    /\ MarkAll({"durable"} \cup (IF ackShadowed'[s] /\ ~ackShadowed[s]
                                 THEN {"ack-shadowed"} ELSE {}))
    /\ UNCHANGED counters
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
    /\ MarkAll({"crash"} \cup (IF zkState[s] = "INITIAL" THEN {"crash-initial"} ELSE {}))
MCRestart(s) == /\ B!Restart(s) /\ Mark("restart") /\ UNCHANGED counters
MCDropMessage(m) ==
    /\ counters.drop < MaxDrop
    /\ B!DropMessage(m)
    /\ counters' = [counters EXCEPT !.drop = @ + 1]
    /\ Mark("drop")
MCDropNewLeaderAck(m) ==
    /\ counters.drop < MaxDrop
    /\ B!DropNewLeaderAck(m)
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
    \/ \E s \in Server : MCFollowerProcessNewLeader(s)
    \/ \E s \in Server : MCFollowerSendNewLeaderAck(s)
    \/ \E m \in nlAckMsgs : MCLeaderProcessNewLeaderAck(m)
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ \E s \in Server : MCFollowerProcessUpToDate(s)
    \/ \E l \in Server, t \in Txn : MCPropose(l, t)
    \/ \E m \in messages : MCReceiveProposal(m)
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
    \/ \E m \in nlAckMsgs : MCDropNewLeaderAck(m)

MCSpec == MCInit /\ [][MCNext]_vars

SeenNames == {"election", "initial-exit", "initial-exit-flushed", "leader",
              "sync", "DIFF", "TRUNC", "SNAP", "newleader-logged",
              "newleader-nondurable", "newleader-ack",
              "newleader-ack-nondurable", "newleader-ack-rejected",
              "newleader-ack-counted", "broadcast", "uptodate", "mutation",
              "durable", "ack-shadowed", "commit", "apply", "snapshot",
              "crash", "crash-initial", "restart", "drop"}

MCTypeOK == /\ counters \in [crash : 0..MaxCrash,
                              drop : 0..MaxDrop,
                              snapshot : 0..MaxSnapshot]
            /\ seen \subseteq SeenNames

\* Negated reachability canaries (a violation is a witness, not a bug).
NotElectionReached == "leader" \notin seen
NotMutationReached == "apply" \notin seen
NotRecoveryReached == ~({"crash", "restart"} \subseteq seen)
NotSyncReached == "sync" \notin seen
NotUpToDateReached == "uptodate" \notin seen
NotNonDurableNewLeaderAckReached == "newleader-ack-nondurable" \notin seen
NotAckShadowReached == "ack-shadowed" \notin seen
NotInitialExitFlushedReached == "initial-exit-flushed" \notin seen

=============================================================================
