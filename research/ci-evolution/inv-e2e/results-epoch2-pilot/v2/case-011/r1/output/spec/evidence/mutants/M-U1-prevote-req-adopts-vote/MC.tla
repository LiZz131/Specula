------------------------------- MODULE MC -------------------------------
EXTENDS base

Old == INSTANCE base

CONSTANTS MaxElectionCount, MaxMembershipCount, MaxCrashCount, MaxDropCount,
          MaxMessageCount

VARIABLE faultCounters
faultVars == <<faultCounters>>
mcVars == <<vars, faultCounters>>

\* Election-timer firings and external election triggers introduce
\* nondeterminism and share the `election` budget. With Pre-Vote, a timer
\* firing may start a Pre-Vote round instead of an election; the election a
\* Pre-Vote quorum later triggers is reactive and is not counted again.
\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:1959-2036 (tick), 1683-1690 (external)
\* update: Update!AffectedActions
MCTickElect(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Old!TickElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

MCExternalElect(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Old!ExternalElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

MCExternalPreElect(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Old!ExternalPreElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

MCStartTransferElection(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Old!StartTransferElection(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

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

\* Reactive steps are not bounded. Named per family so Update.tla can select
\* concrete subsets without copying reference behavior.
MCReactiveVote ==
    \/ \E i \in Server :
          Old!PersistVote(i) \/ Old!FinishVoteBroadcast(i) \/ Old!FlushLog(i)
          \/ Old!ExpireLease(i) \/ Old!Restart(i) \/ Old!RefreshServerState(i)
          \/ Old!CommitMembership(i)
    \/ \E i \in Server, j \in Server :
          Old!SendVoteRequest(i, j) \/ Old!SendAppendEntries(i, j)
    \/ \E m \in messages :
          Old!DeliverVoteRequest(m) \/ Old!DeliverVoteResponse(m)
          \/ Old!DeliverAppendEntries(m)

\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:2342-2344,1551-1562,1803-1820
\* update: Update!AffectedActions
MCReactivePreVote ==
    \/ \E i \in Server : Old!SendPreVoteRequests(i)
    \/ \E m \in messages :
          Old!DeliverPreVoteRequest(m) \/ Old!DeliverPreVoteResponse(m)

MCReactive == MCReactiveVote \/ MCReactivePreVote

MCInit ==
    /\ Init
    /\ faultCounters = [election |-> 0, membership |-> 0, crash |-> 0, drop |-> 0]

MCNext ==
    \/ \E i \in Server : MCTickElect(i) \/ MCExternalElect(i) \/ MCExternalPreElect(i)
                           \/ MCStartTransferElection(i) \/ MCCrash(i)
                           \/ MCAppendUniformConfig(i)
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
\* note:     update: the ghost Pre-Vote round counter is bounded by the election budget, because every round is created by a counted timer/external trigger.
MCTypeOK == /\ TypeOK
            /\ faultCounters \in
                  [election : 0..MaxElectionCount,
                   membership : 0..MaxMembershipCount,
                   crash : 0..MaxCrashCount,
                   drop : 0..MaxDropCount]
            /\ preRound \in [Server -> 0..MaxElectionCount]

ModelView == <<vars, faultCounters>>

=============================================================================
