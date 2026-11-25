------------------------------- MODULE MC -------------------------------
EXTENDS base

Old == INSTANCE base

CONSTANTS MaxElectionCount, MaxMembershipCount, MaxCrashCount, MaxDropCount,
          MaxMessageCount, MaxPreVoteCount

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
\* code: openraft/src/core/raft_core.rs:2010-2036 (tick Pre-Vote), 1683-1696 (external pre_vote)
\* update: Update!AffectedActions
\* Starting a Pre-Vote round introduces nondeterminism (timer/operator), so it
\* is bounded like an election start. Handling Pre-Vote messages is reactive.
MCTickPreVote(i) ==
    /\ faultCounters.preVote < MaxPreVoteCount
    /\ Old!TickPreVote(i)
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

\* Reactive (unbounded) per-node and per-message steps, split so that
\* Update.tla can select them without copying their bodies.
MCReactiveNode(i) ==
    \/ Old!PersistVote(i) \/ Old!FinishVoteBroadcast(i) \/ Old!FlushLog(i)
    \/ Old!ExpireLease(i) \/ Old!Restart(i) \/ Old!RefreshServerState(i)
    \/ Old!CommitMembership(i)

MCReactiveSend(i, j) ==
    Old!SendVoteRequest(i, j) \/ Old!SendAppendEntries(i, j)

MCReactiveMsg(m) ==
    \/ Old!DeliverVoteRequest(m) \/ Old!DeliverVoteResponse(m)
    \/ Old!DeliverAppendEntries(m)
    \/ Old!DeliverPreVoteRequest(m) \/ Old!DeliverPreVoteResponse(m)
    \/ Old!DefaultPreVoteRpcGrant(m)

MCReactive ==
    \/ \E i \in Server : MCReactiveNode(i)
    \/ \E i \in Server, j \in Server : MCReactiveSend(i, j)
    \/ \E m \in messages : MCReactiveMsg(m)

MCInit ==
    /\ Init
    /\ faultCounters = [election |-> 0, membership |-> 0, crash |-> 0, drop |-> 0,
                        preVote |-> 0]

MCNext ==
    \/ \E i \in Server : MCTickElect(i) \/ MCExternalElect(i)
                           \/ MCStartTransferElection(i) \/ MCCrash(i)
                           \/ MCAppendUniformConfig(i)
                           \/ MCTickPreVote(i) \/ MCExternalPreElect(i)
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
\* verified: update
\* review:   ok
\* note:     adds the preVote start counter for the update.
MCTypeOK == TypeOK /\ faultCounters \in
    [election : 0..MaxElectionCount,
     membership : 0..MaxMembershipCount,
     crash : 0..MaxCrashCount,
     drop : 0..MaxDropCount,
     preVote : 0..MaxPreVoteCount]

ModelView == <<vars, faultCounters>>

=============================================================================
