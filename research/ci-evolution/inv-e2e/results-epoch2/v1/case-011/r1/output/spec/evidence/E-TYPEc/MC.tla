------------------------------- MODULE MC -------------------------------
EXTENDS base

Old == INSTANCE base

\* Fault/nondeterminism counters. `election` bounds timer-driven election
\* starts (tick, including the Pre-Vote branch); `external` bounds
\* administrative Raft::trigger().elect(pre_vote) calls and transfer elections.
\* UPDATE-MAP
\* code: openraft/src/raft/trigger.rs:61-63; core/raft_core.rs:2010-2035
\* update: Update.tla "Environment"
CONSTANTS MaxElectionCount, MaxExternalCount, MaxMembershipCount, MaxCrashCount,
          MaxDropCount, MaxMessageCount, MaxRestartCount

VARIABLE faultCounters
faultVars == <<faultCounters>>
mcVars == <<vars, faultCounters>>

MCTickElect(i, pv) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Old!TickElect(i, pv)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

MCExternalElect(i) ==
    /\ faultCounters.external < MaxExternalCount
    /\ Old!ExternalElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.external = @ + 1]

\* UPDATE-MAP code: core/raft_core.rs:1683-1696 (Elect { pre_vote: true })
\* update: Update!AffectedActions
MCExternalPreElect(i) ==
    /\ faultCounters.external < MaxExternalCount
    /\ Old!ExternalPreElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.external = @ + 1]

MCStartTransferElection(i) ==
    /\ faultCounters.external < MaxExternalCount
    /\ Old!StartTransferElection(i)
    /\ faultCounters' = [faultCounters EXCEPT !.external = @ + 1]

MCAppendJointConfig(i, target) ==
    /\ faultCounters.membership < MaxMembershipCount
    /\ Old!AppendJointConfig(i, target)
    /\ faultCounters' = [faultCounters EXCEPT !.membership = @ + 1]

MCAppendUniformConfig(i) ==
    /\ faultCounters.membership < MaxMembershipCount
    /\ Old!AppendUniformConfig(i)
    /\ faultCounters' = [faultCounters EXCEPT !.membership = @ + 1]

MCCrash(i) ==
    /\ faultCounters.crash < MaxCrashCount
    /\ Old!Crash(i)
    /\ faultCounters' = [faultCounters EXCEPT !.crash = @ + 1]

\* Restart is the recovery half of the crash fault. It is bounded separately so
\* that a "node stays down" environment (MaxRestartCount = 0) can be selected
\* without disabling crashes.
MCRestart(i) ==
    /\ faultCounters.restart < MaxRestartCount
    /\ Old!Restart(i)
    /\ faultCounters' = [faultCounters EXCEPT !.restart = @ + 1]

MCDropMessage(m) ==
    /\ faultCounters.drop < MaxDropCount
    /\ Old!DropMessage(m)
    /\ faultCounters' = [faultCounters EXCEPT !.drop = @ + 1]

\* Reactive steps: event handlers, persistence/flush completion, dispatch.
MCReactiveNode(i) ==
    \/ Old!PersistVote(i) \/ Old!FinishVoteBroadcast(i) \/ Old!FlushLog(i)
    \/ Old!ExpireLease(i) \/ Old!RefreshServerState(i)
    \/ Old!CommitMembership(i)
    \/ \E j \in Server : Old!SendVoteRequest(i, j) \/ Old!SendAppendEntries(i, j)

MCReactiveMsg(m) ==
    \/ Old!DeliverVoteRequest(m) \/ Old!DeliverVoteResponse(m)
    \/ Old!DeliverPreVoteRequest(m) \/ Old!DeliverPreVoteResponse(m)
    \/ Old!DeliverAppendEntries(m)

MCReactive ==
    \/ \E i \in Server : MCReactiveNode(i)
    \/ \E m \in messages : MCReactiveMsg(m)

MCInit ==
    /\ Init
    /\ faultCounters = [election |-> 0, external |-> 0, membership |-> 0,
                        crash |-> 0, restart |-> 0, drop |-> 0]

MCNext ==
    \/ \E i \in Server, pv \in BOOLEAN : MCTickElect(i, pv)
    \/ \E i \in Server : MCExternalElect(i) \/ MCExternalPreElect(i)
                           \/ MCStartTransferElection(i) \/ MCCrash(i)
                           \/ MCRestart(i) \/ MCAppendUniformConfig(i)
    \/ \E i \in Server, target \in SUBSET Server : MCAppendJointConfig(i, target)
    \/ \E m \in messages : MCDropMessage(m)
    \/ /\ MCReactive
       /\ UNCHANGED faultCounters

MCSpec == MCInit /\ [][MCNext]_mcVars

MessageBound == Cardinality(messages) <= MaxMessageCount
MCTypeOK == TypeOK /\ faultCounters \in
    [election : 0..MaxElectionCount,
     external : 0..MaxExternalCount,
     membership : 0..MaxMembershipCount,
     crash : 0..MaxCrashCount,
     restart : 0..MaxRestartCount,
     drop : 0..MaxDropCount]

ModelView == <<vars, faultCounters>>

=============================================================================
