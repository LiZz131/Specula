------------------------------- MODULE MC -------------------------------
EXTENDS base

Old == INSTANCE base

CONSTANTS MaxElectionCount, MaxPreVoteCount, MaxMembershipCount, MaxCrashCount,
          MaxDropCount, MaxMessageCount

VARIABLE faultCounters
faultVars == <<faultCounters>>
mcVars == <<vars, faultCounters>>

MCTickElect(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Old!TickElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

MCExternalElect(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Old!ExternalElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

MCStartTransferElection(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Old!StartTransferElection(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

\* UPDATE-MAP
\* code: core/raft_core.rs:2010-2035 (tick pre-vote), 1683-1697 (Elect{pre_vote})
\* update: Update!AffectedActions
\* A Pre-Vote start is an environment-triggered timer/administrator event, so it
\* is bounded like an election start. The election that a pre-vote quorum
\* triggers (HandlePreVoteResponse) is reactive and is bounded only by MaxTerm.
MCTickPreElect(i) ==
    /\ faultCounters.preVote < MaxPreVoteCount
    /\ Old!TickPreElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.preVote = @ + 1]

MCExternalPreElect(i) ==
    /\ faultCounters.preVote < MaxPreVoteCount
    /\ Old!ExternalPreElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.preVote = @ + 1]

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

MCDropMessage(m) ==
    /\ faultCounters.drop < MaxDropCount
    /\ Old!DropMessage(m)
    /\ faultCounters' = [faultCounters EXCEPT !.drop = @ + 1]

MCReactive ==
    \/ \E i \in Server :
          Old!PersistVote(i) \/ Old!FinishVoteBroadcast(i) \/ Old!FlushLog(i)
          \/ Old!ExpireLease(i) \/ Old!Restart(i) \/ Old!RefreshServerState(i)
          \/ Old!CommitMembership(i) \/ Old!FinishPreVoteBroadcast(i)
    \/ \E i \in Server, j \in Server :
          Old!SendVoteRequest(i, j) \/ Old!SendAppendEntries(i, j)
          \/ Old!SendPreVoteRequest(i, j)
    \/ \E m \in messages :
          Old!DeliverVoteRequest(m) \/ Old!DeliverVoteResponse(m)
          \/ Old!DeliverAppendEntries(m)
          \/ Old!DeliverPreVoteRequest(m) \/ Old!DeliverPreVoteResponse(m)

MCInit ==
    /\ Init
    /\ faultCounters = [election |-> 0, preVote |-> 0, membership |-> 0, crash |-> 0, drop |-> 0]

MCNext ==
    \/ \E i \in Server : MCTickElect(i) \/ MCExternalElect(i)
                           \/ MCStartTransferElection(i) \/ MCCrash(i)
                           \/ MCAppendUniformConfig(i)
                           \/ MCTickPreElect(i) \/ MCExternalPreElect(i)
    \/ \E i \in Server, target \in SUBSET Server : MCAppendJointConfig(i, target)
    \/ \E m \in messages : MCDropMessage(m)
    \/ /\ MCReactive
       /\ UNCHANGED faultCounters

MCSpec == MCInit /\ [][MCNext]_mcVars

MessageBound == Cardinality(messages) <= MaxMessageCount
MCTypeOK == TypeOK /\ faultCounters \in
    [election : 0..MaxElectionCount,
     preVote : 0..MaxPreVoteCount,
     membership : 0..MaxMembershipCount,
     crash : 0..MaxCrashCount,
     drop : 0..MaxDropCount]

ModelView == <<vars, faultCounters>>

=============================================================================
