------------------------------- MODULE MC -------------------------------
EXTENDS base

Old == INSTANCE base

CONSTANTS MaxElectionCount, MaxMembershipCount, MaxCrashCount, MaxDropCount,
          MaxMessageCount,
          \* UPDATE-MAP
          \* code: openraft/src/engine/engine_impl.rs:pre_elect;
          \*       openraft/src/core/raft_core.rs:handle_tick_election
          \* update: Update!PreElectFocus
          \* Bound on Pre-Vote rounds started (tick or trigger().elect(true)).
          MaxPreElectCount,
          \* Admin-triggered elections: trigger().elect(_) and leadership
          \* transfer. FALSE restricts a configuration to autonomous (timer and
          \* message driven) behavior; TRUE keeps the full prior MCNext.
          AllowAdminElect

VARIABLE faultCounters
faultVars == <<faultCounters>>
mcVars == <<vars, faultCounters>>

MCTickElect(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Old!TickElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

MCExternalElect(i) ==
    /\ AllowAdminElect
    /\ faultCounters.election < MaxElectionCount
    /\ Old!ExternalElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

MCStartTransferElection(i) ==
    /\ AllowAdminElect
    /\ faultCounters.election < MaxElectionCount
    /\ Old!StartTransferElection(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]

\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:handle_tick_election (pre_vote branch)
\* update: Update!TickPreElectFocus
MCTickPreElect(i) ==
    /\ faultCounters.preElect < MaxPreElectCount
    /\ Old!TickPreElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.preElect = @ + 1]

\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:ExternalCommand::Elect { pre_vote: true }
\* update: Update!AdminPreElect (disabled when AllowAdminElect = FALSE)
MCExternalPreElect(i) ==
    /\ AllowAdminElect
    /\ faultCounters.preElect < MaxPreElectCount
    /\ Old!ExternalPreElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.preElect = @ + 1]

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

\* Reactive (unbounded) steps. Grouped so that focused views in Update.tla can
\* select subsets without duplicating behavior.
MCReactiveVote ==
    \/ \E i \in Server : Old!PersistVote(i) \/ Old!FinishVoteBroadcast(i)
    \/ \E i \in Server, j \in Server : Old!SendVoteRequest(i, j)
    \/ \E m \in messages : Old!DeliverVoteRequest(m) \/ Old!DeliverVoteResponse(m)

\* UPDATE-MAP
\* code: engine_impl.rs:handle_pre_vote_req,handle_pre_vote_resp;
\*       raft_core.rs:handle_pre_vote_request, Notification::PreVoteResponse
\* update: Update!HandlePreVoteRequestFocus, Update!HandlePreVoteResponseFocus
MCReactivePreVote ==
    \E m \in messages : Old!DeliverPreVoteRequest(m) \/ Old!DeliverPreVoteResponse(m)

MCReactiveLeader ==
    \/ \E i \in Server : Old!ExpireLease(i) \/ Old!Restart(i) \/ Old!RefreshServerState(i)
    \/ \E i \in Server, j \in Server : Old!SendAppendEntries(i, j)
    \/ \E m \in messages : Old!DeliverAppendEntries(m)

MCReactiveMembership ==
    \E i \in Server : Old!FlushLog(i) \/ Old!CommitMembership(i)

MCReactive ==
    \/ MCReactiveVote
    \/ MCReactivePreVote
    \/ MCReactiveLeader
    \/ MCReactiveMembership

MCInit ==
    /\ Init
    /\ faultCounters = [election |-> 0, preElect |-> 0, membership |-> 0, crash |-> 0,
                        drop |-> 0, env |-> 0]

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
     preElect : 0..MaxPreElectCount,
     membership : 0..MaxMembershipCount,
     crash : 0..MaxCrashCount,
     drop : 0..MaxDropCount,
     env : 0..10]

ModelView == <<vars, faultCounters>>

=============================================================================
