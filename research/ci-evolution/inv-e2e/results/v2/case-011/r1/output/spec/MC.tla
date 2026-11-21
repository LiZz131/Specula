------------------------------- MODULE MC -------------------------------
EXTENDS base

\* Instance of the reference module, used for original operator access.
Ref == INSTANCE base

CONSTANTS MaxElectionCount, MaxPreVoteCount, MaxMembershipCount, MaxCrashCount,
          MaxDropCount, MaxMessageCount

VARIABLE faultCounters
faultVars == <<faultCounters>>
mcVars == <<vars, faultCounters>>

MCTickElect(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Ref!TickElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

MCExternalElect(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Ref!ExternalElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

MCStartTransferElection(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Ref!StartTransferElection(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:2010-2035 (timer pre_elect),
\*       openraft/src/core/raft_core.rs:1683-1696 (ExternalCommand::Elect { pre_vote: true })
\* update: Update!PreElectAction
\* A Pre-Vote round is introduced by the election timer or an operator; it is
\* bounded like an election start. The reactive Pre-Vote handlers (and the
\* elect() that a Pre-Vote quorum triggers) are not bounded.
MCTickPreElect(i) ==
    /\ faultCounters.prevote < MaxPreVoteCount
    /\ Ref!TickPreElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.prevote = @ + 1]

MCExternalPreElect(i) ==
    /\ faultCounters.prevote < MaxPreVoteCount
    /\ Ref!ExternalPreElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.prevote = @ + 1]

MCAppendJointConfig(i, target) ==
    /\ faultCounters.membership < MaxMembershipCount
    /\ Ref!AppendJointConfig(i, target)
    /\ faultCounters' = [faultCounters EXCEPT !.membership = @ + 1]

MCAppendUniformConfig(i) ==
    /\ faultCounters.membership < MaxMembershipCount
    /\ Ref!AppendUniformConfig(i)
    /\ faultCounters' = [faultCounters EXCEPT !.membership = @ + 1]

MCCrash(i) ==
    /\ faultCounters.crash < MaxCrashCount
    /\ Ref!Crash(i)
    /\ faultCounters' = [faultCounters EXCEPT !.crash = @ + 1]

MCDropMessage(m) ==
    /\ faultCounters.drop < MaxDropCount
    /\ Ref!DropMessage(m)
    /\ faultCounters' = [faultCounters EXCEPT !.drop = @ + 1]

MCReactive ==
    \/ \E i \in Server :
          Ref!PersistVote(i) \/ Ref!FinishVoteBroadcast(i) \/ Ref!FlushLog(i)
          \/ Ref!ExpireLease(i) \/ Ref!Restart(i) \/ Ref!RefreshServerState(i)
          \/ Ref!CommitMembership(i)
    \/ \E i \in Server, j \in Server :
          Ref!SendVoteRequest(i, j) \/ Ref!SendAppendEntries(i, j)
    \/ \E m \in messages :
          Ref!DeliverVoteRequest(m) \/ Ref!DeliverVoteResponse(m)
          \/ Ref!DeliverPreVoteRequest(m) \/ Ref!DeliverPreVoteResponse(m)
          \/ Ref!DeliverAppendEntries(m)

MCInit ==
    /\ Init
    /\ faultCounters = [election |-> 0, prevote |-> 0, membership |-> 0, crash |-> 0, drop |-> 0]

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
\* REQ-EVIDENCE MCTypeOK
\* intent:   TypeOK holds and the bounded-checking fault counters stay within their configured limits.
\* status:   model-internal
\* watch:    none
\* verified: update (pre-vote revision)
\* review:   ok; extended with the Pre-Vote round counter.
MCTypeOK == TypeOK /\ faultCounters \in
    [election : 0..MaxElectionCount,
     prevote : 0..MaxPreVoteCount,
     membership : 0..MaxMembershipCount,
     crash : 0..MaxCrashCount,
     drop : 0..MaxDropCount]

ModelView == <<vars, faultCounters>>

=============================================================================
