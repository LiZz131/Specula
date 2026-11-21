------------------------------- MODULE MC -------------------------------
EXTENDS base

Old == INSTANCE base

CONSTANTS MaxElectionCount, MaxMembershipCount, MaxCrashCount, MaxDropCount,
          MaxMessageCount

VARIABLE faultCounters
\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:1966-1969 (tick skips a Leader),
\*       openraft/src/core/raft_core.rs:1683-1691 (external pre-vote has no leader check)
\* update: Update!PreVoteNeverDemotesEstablishedLeader
\* MC-layer history variable: whether the node was an established leader when
\* its current Pre-Vote round was started. Only read while preCandidateActive.
VARIABLE preRoundFromLeader
faultVars == <<faultCounters>>
mcVars == <<vars, faultCounters, preRoundFromLeader>>

EstablishedLeader(i) ==
    /\ leaderActive[i]
    /\ role[i] = "Leader"
    /\ vote[i].committed
    /\ vote[i].node = i

\* Used only by the two wrappers whose step either starts a new Pre-Vote round
\* (pre_elect queued SendPreVote: preCandidateActive' is TRUE) or elects at
\* once (preCandidateActive' is FALSE, history irrelevant).
RecordPreRound(i) ==
    preRoundFromLeader' = [preRoundFromLeader EXCEPT ![i] =
                              IF preCandidateActive'[i] THEN EstablishedLeader(i) ELSE @]

\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:1959-2036
\* update: Update!AffectedActions
MCTickElect(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Old!TickElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]
    /\ RecordPreRound(i)

MCExternalElect(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Old!ExternalElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]
    /\ UNCHANGED preRoundFromLeader

\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:1683-1691, openraft/src/engine/engine_impl.rs:298-322
\* update: Update!AffectedActions
MCExternalPreElect(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Old!ExternalPreElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]
    /\ RecordPreRound(i)

MCStartTransferElection(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Old!StartTransferElection(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]
    /\ UNCHANGED preRoundFromLeader

MCAppendJointConfig(i, target) ==
    /\ faultCounters.membership < MaxMembershipCount
    /\ Old!AppendJointConfig(i, target)
    /\ faultCounters' = [faultCounters EXCEPT !.membership = @ + 1]
    /\ UNCHANGED preRoundFromLeader

MCAppendUniformConfig(i) ==
    /\ faultCounters.membership < MaxMembershipCount
    /\ Old!AppendUniformConfig(i)
    /\ faultCounters' = [faultCounters EXCEPT !.membership = @ + 1]
    /\ UNCHANGED preRoundFromLeader

MCCrash(i) ==
    /\ faultCounters.crash < MaxCrashCount
    /\ Old!Crash(i)
    /\ faultCounters' = [faultCounters EXCEPT !.crash = @ + 1]
    /\ UNCHANGED preRoundFromLeader

MCDropMessage(m) ==
    /\ faultCounters.drop < MaxDropCount
    /\ Old!DropMessage(m)
    /\ faultCounters' = [faultCounters EXCEPT !.drop = @ + 1]
    /\ UNCHANGED preRoundFromLeader

\* Reactive, unbounded steps. Grouped so Update.tla can select subsets.
MCPersistVote(i) == Old!PersistVote(i)
MCFinishVoteBroadcast(i) == Old!FinishVoteBroadcast(i)
MCFlushLog(i) == Old!FlushLog(i)
MCExpireLease(i) == Old!ExpireLease(i)
MCRestart(i) == Old!Restart(i)
MCRefreshServerState(i) == Old!RefreshServerState(i)
MCCommitMembership(i) == Old!CommitMembership(i)
MCSendVoteRequest(i, j) == Old!SendVoteRequest(i, j)
MCSendAppendEntries(i, j) == Old!SendAppendEntries(i, j)
MCDeliverVoteRequest(m) == Old!DeliverVoteRequest(m)
MCDeliverVoteResponse(m) == Old!DeliverVoteResponse(m)
MCDeliverAppendEntries(m) == Old!DeliverAppendEntries(m)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:414-447,516-554
\* update: Update!AffectedActions
MCDeliverPreVoteRequest(m) == Old!DeliverPreVoteRequest(m)
MCDeliverPreVoteResponse(m) == Old!DeliverPreVoteResponse(m)

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
    /\ faultCounters = [election |-> 0, membership |-> 0, crash |-> 0, drop |-> 0]
    /\ preRoundFromLeader = [i \in Server |-> FALSE]

MCNext ==
    \/ \E i \in Server : MCTickElect(i) \/ MCExternalElect(i)
                           \/ MCExternalPreElect(i)
                           \/ MCStartTransferElection(i) \/ MCCrash(i)
                           \/ MCAppendUniformConfig(i)
    \/ \E i \in Server, target \in SUBSET Server : MCAppendJointConfig(i, target)
    \/ \E m \in messages : MCDropMessage(m)
    \/ /\ MCReactive
       /\ UNCHANGED <<faultCounters, preRoundFromLeader>>

MCSpec == MCInit /\ [][MCNext]_mcVars

MessageBound == Cardinality(messages) <= MaxMessageCount
MCTypeOK == /\ TypeOK
            /\ faultCounters \in
                  [election : 0..MaxElectionCount,
                   membership : 0..MaxMembershipCount,
                   crash : 0..MaxCrashCount,
                   drop : 0..MaxDropCount]
            /\ preRoundFromLeader \in [Server -> BOOLEAN]

ModelView == <<vars, faultCounters, preRoundFromLeader>>

=============================================================================
