------------------------------- MODULE MC -------------------------------
(***************************************************************************
 * Bounded model-checking wrapper for the updated (pre-vote) reference.    *
 * Fault/nondeterminism-introducing actions are counter bounded; reactive  *
 * actions are not.  `preOrigin` is MC framing state that records which   *
 * caller created the currently active pre-vote round (tick timer or       *
 * explicit external trigger); it is consumed only by Update.tla           *
 * properties and never constrains reference behaviour.                    *
 *************************************************************************)
EXTENDS base

Ref == INSTANCE base

CONSTANTS MaxElectionCount, MaxPreVoteCount, MaxMembershipCount, MaxCrashCount,
          MaxDropCount, MaxMessageCount

VARIABLES faultCounters, preOrigin
faultVars == <<faultCounters>>
mcVars == <<vars, faultCounters, preOrigin>>

\* Keep preOrigin canonical: an inactive round has no origin.
SyncOrigin ==
    preOrigin' = [i \in Server |-> IF preCandidateActive'[i] THEN preOrigin[i] ELSE "none"]

MCTickElect(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Ref!TickElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]
    /\ SyncOrigin

MCExternalElect(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Ref!ExternalElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]
    /\ SyncOrigin

MCStartTransferElection(i) ==
    /\ faultCounters.election < MaxElectionCount
    /\ Ref!StartTransferElection(i)
    /\ faultCounters' = [faultCounters EXCEPT !.election = @ + 1]
    /\ SyncOrigin

\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:2012-2035 (tick pre-vote), :1683-1689 (external)
\* update: Update!AffectedActions
MCTickPreElect(i) ==
    /\ faultCounters.preVote < MaxPreVoteCount
    /\ Ref!TickPreElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.preVote = @ + 1]
    /\ preOrigin' = [j \in Server |-> IF ~preCandidateActive'[j] THEN "none"
                                      ELSE IF j = i THEN "tick" ELSE preOrigin[j]]

MCExternalPreElect(i) ==
    /\ faultCounters.preVote < MaxPreVoteCount
    /\ Ref!ExternalPreElect(i)
    /\ faultCounters' = [faultCounters EXCEPT !.preVote = @ + 1]
    /\ preOrigin' = [j \in Server |-> IF ~preCandidateActive'[j] THEN "none"
                                      ELSE IF j = i THEN "external" ELSE preOrigin[j]]

MCAppendJointConfig(i, target) ==
    /\ faultCounters.membership < MaxMembershipCount
    /\ Ref!AppendJointConfig(i, target)
    /\ faultCounters' = [faultCounters EXCEPT !.membership = @ + 1]
    /\ SyncOrigin

MCAppendUniformConfig(i) ==
    /\ faultCounters.membership < MaxMembershipCount
    /\ Ref!AppendUniformConfig(i)
    /\ faultCounters' = [faultCounters EXCEPT !.membership = @ + 1]
    /\ SyncOrigin

MCCrash(i) ==
    /\ faultCounters.crash < MaxCrashCount
    /\ Ref!Crash(i)
    /\ faultCounters' = [faultCounters EXCEPT !.crash = @ + 1]
    /\ SyncOrigin

MCDropMessage(m) ==
    /\ faultCounters.drop < MaxDropCount
    /\ Ref!DropMessage(m)
    /\ faultCounters' = [faultCounters EXCEPT !.drop = @ + 1]
    /\ SyncOrigin

\* Reactive (unbounded) wrappers, named individually so that Update.tla can
\* select them for focused/open campaigns without copying their bodies.
MCPersistVote(i) == Ref!PersistVote(i) /\ UNCHANGED faultCounters /\ SyncOrigin
MCFinishVoteBroadcast(i) == Ref!FinishVoteBroadcast(i) /\ UNCHANGED faultCounters /\ SyncOrigin
MCFlushLog(i) == Ref!FlushLog(i) /\ UNCHANGED faultCounters /\ SyncOrigin
MCExpireLease(i) == Ref!ExpireLease(i) /\ UNCHANGED faultCounters /\ SyncOrigin
MCRestart(i) == Ref!Restart(i) /\ UNCHANGED faultCounters /\ SyncOrigin
MCRefreshServerState(i) == Ref!RefreshServerState(i) /\ UNCHANGED faultCounters /\ SyncOrigin
MCCommitMembership(i) == Ref!CommitMembership(i) /\ UNCHANGED faultCounters /\ SyncOrigin
MCSendVoteRequest(i, j) == Ref!SendVoteRequest(i, j) /\ UNCHANGED faultCounters /\ SyncOrigin
MCSendAppendEntries(i, j) == Ref!SendAppendEntries(i, j) /\ UNCHANGED faultCounters /\ SyncOrigin
MCDeliverVoteRequest(m) == Ref!DeliverVoteRequest(m) /\ UNCHANGED faultCounters /\ SyncOrigin
MCDeliverVoteResponse(m) == Ref!DeliverVoteResponse(m) /\ UNCHANGED faultCounters /\ SyncOrigin
MCDeliverAppendEntries(m) == Ref!DeliverAppendEntries(m) /\ UNCHANGED faultCounters /\ SyncOrigin
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:413-447,515-554; openraft/src/network/v2/network.rs:141-161
\* update: Update!AffectedActions
MCDeliverPreVoteRequest(m) == Ref!DeliverPreVoteRequest(m) /\ UNCHANGED faultCounters /\ SyncOrigin
MCDeliverPreVoteResponse(m) == Ref!DeliverPreVoteResponse(m) /\ UNCHANGED faultCounters /\ SyncOrigin
MCNetworkDefaultPreVote(m) == Ref!NetworkDefaultPreVote(m) /\ UNCHANGED faultCounters /\ SyncOrigin

MCReactive ==
    \/ \E i \in Server :
          MCPersistVote(i) \/ MCFinishVoteBroadcast(i) \/ MCFlushLog(i)
          \/ MCExpireLease(i) \/ MCRestart(i) \/ MCRefreshServerState(i)
          \/ MCCommitMembership(i)
    \/ \E i \in Server, j \in Server :
          MCSendVoteRequest(i, j) \/ MCSendAppendEntries(i, j)
    \/ \E m \in messages :
          MCDeliverVoteRequest(m) \/ MCDeliverVoteResponse(m)
          \/ MCDeliverAppendEntries(m) \/ MCDeliverPreVoteRequest(m)
          \/ MCDeliverPreVoteResponse(m) \/ MCNetworkDefaultPreVote(m)

MCInit ==
    /\ Init
    /\ faultCounters = [election |-> 0, preVote |-> 0, membership |-> 0, crash |-> 0, drop |-> 0]
    /\ preOrigin = [i \in Server |-> "none"]

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
\* REQ-EVIDENCE MCTypeOK
\* intent:   TypeOK holds and the bounded-checking fault counters and origin ghost stay within their configured domains.
\* status:   model-internal
\* watch:    none
\* verified: update
\* review:   extended with the preVote counter and the preOrigin MC ghost.
MCTypeOK == /\ TypeOK
            /\ faultCounters \in
                  [election : 0..MaxElectionCount,
                   preVote : 0..MaxPreVoteCount,
                   membership : 0..MaxMembershipCount,
                   crash : 0..MaxCrashCount,
                   drop : 0..MaxDropCount]
            /\ preOrigin \in [Server -> {"none", "tick", "external"}]
            /\ \A i \in Server : (preOrigin[i] = "none") <=> ~preCandidateActive[i]

ModelView == <<vars, faultCounters, preOrigin>>

=============================================================================
