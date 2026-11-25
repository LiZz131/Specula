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
\* UPDATE-MAP code: quorum/Learner.java:561-565 update: Update!AffectedActions
MCCompleteSync(s) ==
    /\ B!CompleteSync(s)
    /\ seen' = IF syncMode[s] = "DIFF" /\ Len(proposed'[s]) > Len(queued[s])
               THEN seen \cup {"diffpayload"} ELSE seen
    /\ UNCHANGED counters
MCPersistCurrentEpoch(s) == /\ B!PersistCurrentEpoch(s) /\ UNCHANGED mcVars
\* UPDATE-MAP code: quorum/Learner.java:749-751 update: Update!AffectedActions
MCClearSyncMode(s) == /\ B!ClearSyncMode(s) /\ UNCHANGED mcVars
\* UPDATE-MAP code: quorum/Learner.java:752-757,777-783 update: Update!AffectedActions
MCLogSyncProposal(s) == /\ B!LogSyncProposal(s) /\ Mark("synclog") /\ UNCHANGED counters
\* UPDATE-MAP code: quorum/Learner.java:760 update: Update!AffectedActions
MCAckNewLeader(s) ==
    /\ B!AckNewLeader(s)
    /\ seen' = IF Len(durable[s]) < Len(queued[s])
               THEN seen \cup {"nlack", "nlackBeforeDurable"}
               ELSE seen \cup {"nlack"}
    /\ UNCHANGED counters
MCCountNewLeaderAck(l, s) == /\ B!CountNewLeaderAck(l, s) /\ UNCHANGED mcVars
MCLeaderBroadcast(l) == /\ B!LeaderBroadcast(l) /\ Mark("broadcast") /\ UNCHANGED counters
\* UPDATE-MAP code: quorum/Learner.java:765-767 update: Update!AffectedActions
MCReceiveUpToDate(s) == /\ B!ReceiveUpToDate(s) /\ Mark("uptodate") /\ UNCHANGED counters
MCEnterBroadcast(s) == /\ B!EnterBroadcast(s) /\ UNCHANGED mcVars
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
    \/ \E s \in Server : MCCompleteSync(s)
    \/ \E s \in Server : MCPersistCurrentEpoch(s)
    \/ \E s \in Server : MCClearSyncMode(s)
    \/ \E s \in Server : MCLogSyncProposal(s)
    \/ \E s \in Server : MCAckNewLeader(s)
    \/ \E l, s \in Server : MCCountNewLeaderAck(l, s)
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ \E s \in Server : MCReceiveUpToDate(s)
    \/ \E s \in Server : MCEnterBroadcast(s)
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

MilestoneNames == {"election", "leader", "sync", "DIFF", "TRUNC", "SNAP",
                   "diffpayload", "synclog", "nlack", "nlackBeforeDurable",
                   "uptodate", "broadcast", "mutation", "durable", "commit",
                   "apply", "snapshot", "crash", "restart", "drop"}

\* REQ-EVIDENCE MCTypeOK
\* intent:   The model-checking fault counters stay within their configured bounds and the milestone set holds only known milestone names.
\* status:   model-internal
\* watch:    none (observer bookkeeping of the model-checking harness)
\* verified: update
\* review:   ok
MCTypeOK == /\ counters \in [crash : 0..MaxCrash,
                              drop : 0..MaxDrop,
                              snapshot : 0..MaxSnapshot]
            /\ seen \subseteq MilestoneNames

\* REQ-EVIDENCE NotElectionReached
\* intent:   Reachability canary, expected to be violated: no election win (milestone leader) has occurred yet.
\* status:   model-internal
\* watch:    none (reachability canary)
\* verified: update
\* review:   ok
NotElectionReached == "leader" \notin seen
\* REQ-EVIDENCE NotMutationReached
\* intent:   Reachability canary, expected to be violated: no transaction has been applied yet (milestone apply).
\* status:   model-internal
\* watch:    none (reachability canary)
\* verified: update
\* review:   ok
NotMutationReached == "apply" \notin seen
\* REQ-EVIDENCE NotRecoveryReached
\* intent:   Reachability canary, expected to be violated: no run has yet seen both a crash and a restart.
\* status:   model-internal
\* watch:    none (reachability canary)
\* verified: update
\* review:   ok
NotRecoveryReached == ~({"crash", "restart"} \subseteq seen)
\* REQ-EVIDENCE NotSyncReached
\* intent:   Reachability canary, expected to be violated: no synchronization mode has been selected yet (milestone sync).
\* status:   model-internal
\* watch:    none (reachability canary)
\* verified: update
\* review:   ok
NotSyncReached == "sync" \notin seen

=============================================================================
