------------------------------- MODULE MC -------------------------------
\* Incremental revision for update 2efbdfc: wrappers for the split learner
\* NEWLEADER/UPTODATE handlers replace PersistCurrentEpoch/EnterBroadcast/
\* ClearSyncMode.  Fault actions remain counter-bounded.
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
MCCompleteSync(s) == /\ B!CompleteSync(s) /\ UNCHANGED mcVars
\* UPDATE-MAP
\* code: server/quorum/Learner.java:726-761
\* update: Update!AffectedActions
MCSyncWithLeaderNewLeader(s) ==
    /\ B!SyncWithLeaderNewLeader(s)
    /\ seen' = seen \cup {"newleader"} \cup
                 (IF syncBuf[s] /= <<>> THEN {"newleaderLogged"} ELSE {})
    /\ UNCHANGED counters
\* UPDATE-MAP
\* code: server/quorum/Learner.java:764-785
\* update: Update!AffectedActions
MCSyncWithLeaderUpToDate(s) == /\ B!SyncWithLeaderUpToDate(s) /\ Mark("uptodate") /\ UNCHANGED counters
MCLeaderBroadcast(l) == /\ B!LeaderBroadcast(l) /\ Mark("broadcast") /\ UNCHANGED counters
MCPropose(l, t) == /\ B!Propose(l, t) /\ Mark("mutation") /\ UNCHANGED counters
MCReceiveProposal(m) == /\ B!ReceiveProposal(m) /\ UNCHANGED mcVars
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
    \/ \E s \in Server : MCSyncWithLeaderNewLeader(s)
    \/ \E s \in Server : MCSyncWithLeaderUpToDate(s)
    \/ \E l \in Server : MCLeaderBroadcast(l)
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

MCSpec == MCInit /\ [][MCNext]_<<allVars, mcVars>>

\* REQ-EVIDENCE MCTypeOK
\* intent:   The model-checking fault counters stay within their configured bounds and the milestone set holds only known milestone names.
\* status:   model-internal
\* watch:    none (observer bookkeeping of the model-checking harness)
\* verified: update (2efbdfc); milestone names extended
\* review:   ok
MCTypeOK == /\ counters \in [crash : 0..MaxCrash,
                              drop : 0..MaxDrop,
                              snapshot : 0..MaxSnapshot]
            /\ seen \subseteq {"election", "leader", "sync", "DIFF",
                                "TRUNC", "SNAP", "broadcast", "mutation",
                                "durable", "commit", "apply", "snapshot",
                                "crash", "restart", "drop", "newleader",
                                "newleaderLogged", "uptodate"}

\* REQ-EVIDENCE NotElectionReached
\* intent:   Reachability canary, expected to be violated: no election win (milestone leader) has occurred yet.
\* status:   model-internal
\* watch:    none (reachability canary)
\* verified: base
\* review:   ok
NotElectionReached == "leader" \notin seen
\* REQ-EVIDENCE NotMutationReached
\* intent:   Reachability canary, expected to be violated: no transaction has been applied yet (milestone apply).
\* status:   model-internal
\* watch:    none (reachability canary)
\* verified: base
\* review:   ok
NotMutationReached == "apply" \notin seen
\* REQ-EVIDENCE NotRecoveryReached
\* intent:   Reachability canary, expected to be violated: no run has yet seen both a crash and a restart.
\* status:   model-internal
\* watch:    none (reachability canary)
\* verified: base
\* review:   ok
NotRecoveryReached == ~({"crash", "restart"} \subseteq seen)
\* REQ-EVIDENCE NotSyncReached
\* intent:   Reachability canary, expected to be violated: no synchronization mode has been selected yet (milestone sync).
\* status:   model-internal
\* watch:    none (reachability canary)
\* verified: base
\* review:   ok
NotSyncReached == "sync" \notin seen
\* REQ-EVIDENCE NotNewLeaderLoggedReached
\* intent:   Reachability canary, expected to be violated: no learner has yet handled NEWLEADER with buffered sync proposals (the updated logging path).
\* status:   model-internal
\* watch:    zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader
\* verified: update (2efbdfc)
\* review:   ok
NotNewLeaderLoggedReached == "newleaderLogged" \notin seen
\* REQ-EVIDENCE NotUpToDateReached
\* intent:   Reachability canary, expected to be violated: no learner has yet completed UPTODATE.
\* status:   model-internal
\* watch:    zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader
\* verified: update (2efbdfc)
\* review:   ok
NotUpToDateReached == "uptodate" \notin seen

=============================================================================
