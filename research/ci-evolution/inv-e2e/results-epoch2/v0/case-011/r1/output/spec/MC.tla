------------------------------- MODULE MC -------------------------------
EXTENDS base

\* Instance used for operator access from cfg overrides and wrappers.
Ref == INSTANCE base

\* MaxElectionCount bounds direct election starts (timer elect, external
\* elect(false), leadership transfer). MaxPreVoteCount bounds Pre-Vote round
\* starts (timer or ExternalCommand::Elect { pre_vote: true }). A Pre-Vote
\* quorum that calls elect() is reactive and is bounded only by MaxTerm.
\* AllowDirectOperatorElect gates the operator-only direct paths
\* (Trigger::elect(false), leadership transfer); AllowExternalPreElect gates
\* Trigger::elect(true).
CONSTANTS MaxElectionCount, MaxPreVoteCount, MaxMembershipCount, MaxCrashCount,
          MaxDropCount, MaxMessageCount, AllowDirectOperatorElect,
          AllowExternalPreElect

ASSUME /\ AllowDirectOperatorElect \in BOOLEAN
       /\ AllowExternalPreElect \in BOOLEAN

VARIABLE faultCounters
faultVars == <<faultCounters>>
mcVars == <<vars, faultCounters>>

MCTickElect(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Ref!TickElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:2010-2035 (timer Pre-Vote branch)
\* update: Update!AffectedActions
MCTickPreElect(i) ==
    /\ faultCounters.preVote < MaxPreVoteCount
    /\ Ref!TickPreElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.preVote = @ + 1]

MCExternalElect(i) ==
    /\ AllowDirectOperatorElect
    /\ faultCounters.election < MaxElectionCount
    /\ Ref!ExternalElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:1683-1695, raft/trigger.rs:Trigger::elect
\* update: Update!AffectedActions
MCExternalPreElect(i) ==
    /\ AllowExternalPreElect
    /\ faultCounters.preVote < MaxPreVoteCount
    /\ Ref!ExternalPreElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.preVote = @ + 1]

MCStartTransferElection(i) ==
    /\ AllowDirectOperatorElect
    /\ faultCounters.election < MaxElectionCount
    /\ Ref!StartTransferElection(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

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

\* Reactive steps are not counter-bounded. They are named individually so
\* that Update.tla can select them without copying their bodies.
MCPersistVote(i) == Ref!PersistVote(i) /\ UNCHANGED faultVars
MCFinishVoteBroadcast(i) == Ref!FinishVoteBroadcast(i) /\ UNCHANGED faultVars
MCFlushLog(i) == Ref!FlushLog(i) /\ UNCHANGED faultVars
MCExpireLease(i) == Ref!ExpireLease(i) /\ UNCHANGED faultVars
MCRestart(i) == Ref!Restart(i) /\ UNCHANGED faultVars
MCRefreshServerState(i) == Ref!RefreshServerState(i) /\ UNCHANGED faultVars
MCCommitMembership(i) == Ref!CommitMembership(i) /\ UNCHANGED faultVars
MCSendVoteRequest(i, j) == Ref!SendVoteRequest(i, j) /\ UNCHANGED faultVars
MCSendAppendEntries(i, j) == Ref!SendAppendEntries(i, j) /\ UNCHANGED faultVars
MCDeliverVoteRequest(m) == Ref!DeliverVoteRequest(m) /\ UNCHANGED faultVars
MCDeliverVoteResponse(m) == Ref!DeliverVoteResponse(m) /\ UNCHANGED faultVars
MCDeliverAppendEntries(m) == Ref!DeliverAppendEntries(m) /\ UNCHANGED faultVars
\* UPDATE-MAP
\* code: engine_impl.rs:406-447 / 511-554, raft_core.rs:1551-1562, 1803-1820
\* update: Update!AffectedActions
MCDeliverPreVoteRequest(m) == Ref!DeliverPreVoteRequest(m) /\ UNCHANGED faultVars
MCDeliverPreVoteResponse(m) == Ref!DeliverPreVoteResponse(m) /\ UNCHANGED faultVars

MCReactive ==
    \/ \E i \in Server :
          MCPersistVote(i) \/ MCFinishVoteBroadcast(i) \/ MCFlushLog(i)
          \/ MCExpireLease(i) \/ MCRestart(i) \/ MCRefreshServerState(i)
          \/ MCCommitMembership(i)
    \/ \E i \in Server, j \in Server :
          MCSendVoteRequest(i, j) \/ MCSendAppendEntries(i, j)
    \/ \E m \in messages :
          MCDeliverVoteRequest(m) \/ MCDeliverVoteResponse(m)
          \/ MCDeliverAppendEntries(m)
          \/ MCDeliverPreVoteRequest(m) \/ MCDeliverPreVoteResponse(m)

MCInit ==
    /\ Init
    /\ faultCounters = [election |-> 0, preVote |-> 0, membership |-> 0,
                        crash |-> 0, drop |-> 0]

MCNext ==
    \/ \E i \in Server : MCTickElect(i) \/ MCTickPreElect(i) \/ MCExternalElect(i)
                           \/ MCExternalPreElect(i) \/ MCStartTransferElection(i)
                           \/ MCCrash(i) \/ MCAppendUniformConfig(i)
    \/ \E i \in Server, target \in SUBSET Server : MCAppendJointConfig(i, target)
    \/ \E m \in messages : MCDropMessage(m)
    \/ MCReactive

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
