------------------------------- MODULE MC -------------------------------
(* Model-checking wrapper for the updated reference suite.  Fault actions  *)
(* are counter-bounded; `seen` records reachability canaries;              *)
(* `everCommitted` is the longest history ever committed by any server     *)
(* (ghost used by committed-history properties).                           *)
EXTENDS base

B == INSTANCE base

CONSTANTS MaxCrash, MaxDrop, MaxSnapshot
ASSUME /\ MaxCrash \in Nat /\ MaxDrop \in Nat /\ MaxSnapshot \in Nat

VARIABLES counters, seen, everCommitted
mcVars == <<counters, seen, everCommitted>>
mcAllVars == <<allVars, mcVars>>

MCInit ==
    /\ Init
    /\ counters = [crash |-> 0, drop |-> 0, snapshot |-> 0]
    /\ seen = {}
    /\ everCommitted = <<>>

Mark(name) == seen' = seen \cup {name}
MarkAll(names) == seen' = seen \cup names

MCBeginElection(s) == /\ B!BeginElection(s) /\ Mark("election") /\ UNCHANGED counters
MCLearnerAbort(s) == /\ B!LearnerAbort(s) /\ Mark("abort") /\ UNCHANGED counters
MCCastVote(v, c) == /\ B!CastVote(v, c) /\ UNCHANGED <<counters, seen>>
MCWinElection(s) == /\ B!WinElection(s) /\ Mark("leader") /\ UNCHANGED counters
MCFollowLeader(s, l) == /\ B!FollowLeader(s, l) /\ UNCHANGED <<counters, seen>>
MCAcceptEpoch(s) == /\ B!AcceptEpoch(s) /\ UNCHANGED <<counters, seen>>
MCFinishDiscovery(l) == /\ B!FinishDiscovery(l) /\ UNCHANGED <<counters, seen>>
MCEnterSyncPhase(s, l) == /\ B!EnterSyncPhase(s, l) /\ UNCHANGED <<counters, seen>>
MCSelectSync(s, l, mode) ==
    /\ B!SelectSync(s, l, mode)
    /\ MarkAll({"sync", mode} \cup (IF Established(l) THEN {"lateSync"} ELSE {}))
    /\ UNCHANGED counters
MCLeaderQueueNewLeader(l, s) == /\ B!LeaderQueueNewLeader(l, s) /\ UNCHANGED <<counters, seen>>
MCLearnerProposal(s) == /\ B!LearnerProposal(s) /\ UNCHANGED <<counters, seen>>
MCLearnerCommit(s) ==
    /\ B!LearnerCommit(s)
    /\ MarkAll(IF syncStage[s] = "nlAcked" THEN {"commitAfterNewLeader"} ELSE {})
    /\ UNCHANGED counters
MCLearnerNewLeader(s) == /\ B!LearnerNewLeader(s) /\ Mark("newleader") /\ UNCHANGED counters
MCLearnerStartupWithoutServing(s) == /\ B!LearnerStartupWithoutServing(s) /\ UNCHANGED <<counters, seen>>
MCLearnerLogPending(s) == /\ B!LearnerLogPending(s) /\ Mark("logAtNewLeader") /\ UNCHANGED counters
MCLearnerAckNewLeader(s) ==
    /\ B!LearnerAckNewLeader(s)
    /\ MarkAll(IF ~IsPrefix(syncTarget[s], durable[s]) THEN {"nlAck", "nlAckNotDurable"} ELSE {"nlAck"})
    /\ UNCHANGED counters
MCLeaderReceiveNewLeaderAck(m) == /\ B!LeaderReceiveNewLeaderAck(m) /\ UNCHANGED <<counters, seen>>
MCLeaderBroadcast(l) == /\ B!LeaderBroadcast(l) /\ Mark("broadcast") /\ UNCHANGED counters
MCLeaderQueueUpToDate(l, s) == /\ B!LeaderQueueUpToDate(l, s) /\ UNCHANGED <<counters, seen>>
MCLearnerUpToDate(s) == /\ B!LearnerUpToDate(s) /\ Mark("uptodate") /\ UNCHANGED counters
MCLearnerLogAfterUpToDate(s) == /\ B!LearnerLogAfterUpToDate(s) /\ UNCHANGED <<counters, seen>>
MCLearnerCommitAfterUpToDate(s) == /\ B!LearnerCommitAfterUpToDate(s) /\ UNCHANGED <<counters, seen>>
MCEnterBroadcast(s) == /\ B!EnterBroadcast(s) /\ Mark("followerBroadcast") /\ UNCHANGED counters
MCPropose(l, t) == /\ B!Propose(l, t) /\ Mark("mutation") /\ UNCHANGED counters
MCReceiveProposal(m) == /\ B!ReceiveProposal(m) /\ UNCHANGED <<counters, seen>>
MCAppendOne(s) == /\ B!AppendOne(s) /\ UNCHANGED <<counters, seen>>
MCFsyncOne(s) == /\ B!FsyncOne(s) /\ Mark("durable") /\ UNCHANGED counters
MCDeliverAck(m) == /\ B!DeliverAck(m) /\ UNCHANGED <<counters, seen>>
MCCommit(l, t) == /\ B!Commit(l, t) /\ Mark("commit") /\ UNCHANGED counters
MCReceiveCommit(m) == /\ B!ReceiveCommit(m) /\ UNCHANGED <<counters, seen>>
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

\* Ghost maintenance: remember the longest committed history ever observed.
LongestCommittedNow == CHOOSE h \in {committed'[s] : s \in Server} :
                          \A s \in Server : Len(committed'[s]) <= Len(h)
UpdateEverCommitted ==
    everCommitted' = IF Len(LongestCommittedNow) > Len(everCommitted)
                     THEN LongestCommittedNow ELSE everCommitted

MCActions ==
    \/ \E s \in Server : MCBeginElection(s)
    \/ \E s \in Server : MCLearnerAbort(s)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s \in Server : MCWinElection(s)
    \/ \E s, l \in Server : MCFollowLeader(s, l)
    \/ \E s \in Server : MCAcceptEpoch(s)
    \/ \E l \in Server : MCFinishDiscovery(l)
    \/ \E s, l \in Server : MCEnterSyncPhase(s, l)
    \/ \E s, l \in Server, mode \in SyncModes \ {"NONE"} : MCSelectSync(s, l, mode)
    \/ \E l, s \in Server : MCLeaderQueueNewLeader(l, s)
    \/ \E s \in Server : MCLearnerProposal(s)
    \/ \E s \in Server : MCLearnerCommit(s)
    \/ \E s \in Server : MCLearnerNewLeader(s)
    \/ \E s \in Server : MCLearnerStartupWithoutServing(s)
    \/ \E s \in Server : MCLearnerLogPending(s)
    \/ \E s \in Server : MCLearnerAckNewLeader(s)
    \/ \E m \in messages : MCLeaderReceiveNewLeaderAck(m)
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ \E l, s \in Server : MCLeaderQueueUpToDate(l, s)
    \/ \E s \in Server : MCLearnerUpToDate(s)
    \/ \E s \in Server : MCLearnerLogAfterUpToDate(s)
    \/ \E s \in Server : MCLearnerCommitAfterUpToDate(s)
    \/ \E s \in Server : MCEnterBroadcast(s)
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

MCNext == MCActions /\ UpdateEverCommitted

MCSpec == MCInit /\ [][MCNext]_mcAllVars

MCTypeOK == /\ counters \in [crash : 0..MaxCrash,
                              drop : 0..MaxDrop,
                              snapshot : 0..MaxSnapshot]
            /\ seen \subseteq {"election", "abort", "leader", "sync", "DIFF",
                                "TRUNC", "SNAP", "lateSync", "commitAfterNewLeader",
                                "newleader", "logAtNewLeader", "nlAck",
                                "nlAckNotDurable", "broadcast", "uptodate",
                                "followerBroadcast", "mutation", "durable",
                                "commit", "apply", "snapshot", "crash",
                                "restart", "drop"}
            /\ everCommitted \in Seq(Entry)

\* Reachability canaries (expected to be violated: each violation is a witness).
NotElectionReached == "leader" \notin seen
NotMutationReached == "apply" \notin seen
NotRecoveryReached == ~({"crash", "restart"} \subseteq seen)
NotSyncReached == "sync" \notin seen
NotFollowerBroadcastReached == "followerBroadcast" \notin seen
NotLateSyncReached == "lateSync" \notin seen
NotCommitAfterNewLeaderReached == "commitAfterNewLeader" \notin seen
NotNlAckNotDurableReached == "nlAckNotDurable" \notin seen
NotLogAtNewLeaderReached == "logAtNewLeader" \notin seen

\* Bounded-depth helper for canonical/limited runs.
DepthBound(n) == TLCGet("level") <= n

=============================================================================
