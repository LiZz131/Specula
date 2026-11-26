------------------------------- MODULE MC -------------------------------
EXTENDS base

Old == INSTANCE base

CONSTANTS MaxElectionCount, MaxPreElectionCount, MaxMembershipCount,
          MaxCrashCount, MaxDropCount, MaxMessageCount

VARIABLE faultCounters

(***************************************************************************
 * Observer (not implementation state): the local vote at the moment the   *
 * current Pre-Vote round was started (Engine::pre_elect reads             *
 * state.vote to build the hypothetical next-term vote,                     *
 * engine_impl.rs:298-302). It is written only by the Pre-Vote wrappers     *
 * and read only by Update.tla properties while a round is active; it does  *
 * not constrain any reference action.                                      *
 *************************************************************************)
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:pre_elect
\* update: Update!PreVoteElectionPremiseCurrent
VARIABLE preVoteBase

faultVars == <<faultCounters>>
observerVars == <<preVoteBase>>
mcVars == <<vars, faultCounters, preVoteBase>>

MCTickElect(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Old!TickElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]
    /\ UNCHANGED observerVars

MCExternalElect(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Old!ExternalElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]
    /\ UNCHANGED observerVars

MCStartTransferElection(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Old!StartTransferElection(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]
    /\ UNCHANGED observerVars

\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:handle_tick_election (pre_vote branch),
\*       openraft/src/core/raft_core.rs:ExternalCommand::Elect { pre_vote: true }
\* update: Update!AffectedActions
MCTickPreElect(i) ==
    /\ faultCounters.preElection < MaxPreElectionCount
    /\ Old!TickPreElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.preElection = @ + 1]
    /\ preVoteBase' = [preVoteBase EXCEPT ![i] = vote[i]]

MCExternalPreElect(i) ==
    /\ faultCounters.preElection < MaxPreElectionCount
    /\ Old!ExternalPreElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.preElection = @ + 1]
    /\ preVoteBase' = [preVoteBase EXCEPT ![i] = vote[i]]

MCAppendJointConfig(i, target) ==
    /\ faultCounters.membership < MaxMembershipCount
    /\ Old!AppendJointConfig(i, target)
    /\ faultCounters' = [faultCounters EXCEPT !.membership = @ + 1]
    /\ UNCHANGED observerVars

MCAppendUniformConfig(i) ==
    /\ faultCounters.membership < MaxMembershipCount
    /\ Old!AppendUniformConfig(i)
    /\ faultCounters' = [faultCounters EXCEPT !.membership = @ + 1]
    /\ UNCHANGED observerVars

MCCrash(i) ==
    /\ faultCounters.crash < MaxCrashCount
    /\ Old!Crash(i)
    /\ faultCounters' = [faultCounters EXCEPT !.crash = @ + 1]
    /\ UNCHANGED observerVars

MCDropMessage(m) ==
    /\ faultCounters.drop < MaxDropCount
    /\ Old!DropMessage(m)
    /\ faultCounters' = [faultCounters EXCEPT !.drop = @ + 1]
    /\ UNCHANGED observerVars

\* Reactive actions are not bounded. Named individually so Update.tla can
\* select interaction subsets without copying any action body.
MCPersistVote(i)          == Old!PersistVote(i) /\ UNCHANGED <<faultVars, observerVars>>
MCFinishVoteBroadcast(i)  == Old!FinishVoteBroadcast(i) /\ UNCHANGED <<faultVars, observerVars>>
MCFlushLog(i)             == Old!FlushLog(i) /\ UNCHANGED <<faultVars, observerVars>>
MCExpireLease(i)          == Old!ExpireLease(i) /\ UNCHANGED <<faultVars, observerVars>>
MCRestart(i)              == Old!Restart(i) /\ UNCHANGED <<faultVars, observerVars>>
MCRefreshServerState(i)   == Old!RefreshServerState(i) /\ UNCHANGED <<faultVars, observerVars>>
MCCommitMembership(i)     == Old!CommitMembership(i) /\ UNCHANGED <<faultVars, observerVars>>
MCSendVoteRequest(i, j)   == Old!SendVoteRequest(i, j) /\ UNCHANGED <<faultVars, observerVars>>
MCSendAppendEntries(i, j) == Old!SendAppendEntries(i, j) /\ UNCHANGED <<faultVars, observerVars>>
MCDeliverVoteRequest(m)   == Old!DeliverVoteRequest(m) /\ UNCHANGED <<faultVars, observerVars>>
MCDeliverVoteResponse(m)  == Old!DeliverVoteResponse(m) /\ UNCHANGED <<faultVars, observerVars>>
MCDeliverAppendEntries(m) == Old!DeliverAppendEntries(m) /\ UNCHANGED <<faultVars, observerVars>>
MCDeliverPreVoteRequest(m)  == Old!DeliverPreVoteRequest(m) /\ UNCHANGED <<faultVars, observerVars>>
MCDeliverPreVoteResponse(m) == Old!DeliverPreVoteResponse(m) /\ UNCHANGED <<faultVars, observerVars>>

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
    /\ faultCounters = [election |-> 0, preElection |-> 0, membership |-> 0,
                        crash |-> 0, drop |-> 0]
    /\ preVoteBase = vote

MCNext ==
    \/ \E i \in Server : MCTickElect(i) \/ MCExternalElect(i)
                           \/ MCStartTransferElection(i) \/ MCCrash(i)
                           \/ MCAppendUniformConfig(i)
                           \/ MCTickPreElect(i) \/ MCExternalPreElect(i)
    \/ \E i \in Server, target \in SUBSET Server : MCAppendJointConfig(i, target)
    \/ \E m \in messages : MCDropMessage(m)
    \/ MCReactive

MCSpec == MCInit /\ [][MCNext]_mcVars

MessageBound == Cardinality(messages) <= MaxMessageCount
MCTypeOK ==
    /\ TypeOK
    /\ faultCounters \in
          [election : 0..MaxElectionCount,
           preElection : 0..MaxPreElectionCount,
           membership : 0..MaxMembershipCount,
           crash : 0..MaxCrashCount,
           drop : 0..MaxDropCount]
    /\ preVoteBase \in [Server -> [term : 0..MaxTerm, node : Server, committed : BOOLEAN]]

(***************************************************************************
 * View: inactive pre-candidate fields and the observer are never read      *
 * (every reader is guarded by preCandidateActive and PreElect overwrites    *
 * them), so they are canonicalized to keep stale values from multiplying   *
 * states.                                                                  *
 *************************************************************************)
PreVoteView == [i \in Server |->
    IF preCandidateActive[i]
    THEN <<preCandidateVote[i], preCandidateConfig[i], preGrants[i], preVoteBase[i]>>
    ELSE <<>>]

ModelView == <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
               configVars, messages, PreVoteView, faultCounters>>

=============================================================================
