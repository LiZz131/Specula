------------------------------- MODULE MC -------------------------------
(***************************************************************************)
(* Model-checking wrapper over the updated reference base.tla.             *)
(* Fault-introducing actions (crash, message loss, background snapshot)    *)
(* are counter bounded; every reactive protocol action is unbounded.       *)
(* Reachability canaries are state predicates over reference variables     *)
(* (the prior `seen` set was removed so that VIEW/symmetry stay exact).    *)
(***************************************************************************)
EXTENDS base

CONSTANTS MaxCrash, MaxDrop, MaxSnapshot
ASSUME /\ MaxCrash \in Nat /\ MaxDrop \in Nat /\ MaxSnapshot \in Nat

VARIABLES counters
mcVars == <<counters>>
vars == <<allVars, counters>>

MCInit ==
    /\ Init
    /\ counters = [crash |-> 0, drop |-> 0, snapshot |-> 0]

\* Reactive / protocol actions: unbounded pass-through wrappers.
MCBeginElection(s) == BeginElection(s) /\ UNCHANGED counters
MCRestartElectionRound(s) == RestartElectionRound(s) /\ UNCHANGED counters
MCCastVote(v, c) == CastVote(v, c) /\ UNCHANGED counters
MCWinElection(s) == WinElection(s) /\ UNCHANGED counters
MCFollowLeader(s, l) == FollowLeader(s, l) /\ UNCHANGED counters
MCStartLeading(s) == StartLeading(s) /\ UNCHANGED counters
MCStartFollowing(s) == StartFollowing(s) /\ UNCHANGED counters
MCLeaderProposeEpoch(s) == LeaderProposeEpoch(s) /\ UNCHANGED counters
MCAcceptEpoch(s) == AcceptEpoch(s) /\ UNCHANGED counters
MCSendAckEpoch(s) == SendAckEpoch(s) /\ UNCHANGED counters
MCLeaderPersistEpoch(s) == LeaderPersistEpoch(s) /\ UNCHANGED counters
MCLeaderStartSync(s) == LeaderStartSync(s) /\ UNCHANGED counters
MCEnterSyncPhase(s) == EnterSyncPhase(s) /\ UNCHANGED counters
MCSyncDiff(s) == SyncDiff(s) /\ UNCHANGED counters
MCSyncTrunc(s) == SyncTrunc(s) /\ UNCHANGED counters
MCSyncSnap(s) == SyncSnap(s) /\ UNCHANGED counters
MCReceiveSyncProposal(m) == ReceiveSyncProposal(m) /\ UNCHANGED counters
MCReceiveSyncCommit(m) == ReceiveSyncCommit(m) /\ UNCHANGED counters
MCPersistCurrentEpoch(s) == PersistCurrentEpoch(s) /\ UNCHANGED counters
MCClearSyncMode(s) == ClearSyncMode(s) /\ UNCHANGED counters
MCStartupWithoutServing(s) == StartupWithoutServing(s) /\ UNCHANGED counters
MCLogSyncProposal(s) == LogSyncProposal(s) /\ UNCHANGED counters
MCSendNewLeaderAck(s) == SendNewLeaderAck(s) /\ UNCHANGED counters
MCReceiveNewLeaderAck(m) == ReceiveNewLeaderAck(m) /\ UNCHANGED counters
MCStartServing(s) == StartServing(s) /\ UNCHANGED counters
MCCommitSyncPacket(s) == CommitSyncPacket(s) /\ UNCHANGED counters
MCEnterBroadcast(s) == EnterBroadcast(s) /\ UNCHANGED counters
MCLeaderActivate(s) == LeaderActivate(s) /\ UNCHANGED counters
MCLeaderEnterBroadcast(s) == LeaderEnterBroadcast(s) /\ UNCHANGED counters
MCPropose(l, t) == Propose(l, t) /\ UNCHANGED counters
MCReceiveProposal(m) == ReceiveProposal(m) /\ UNCHANGED counters
MCAppendOne(s) == AppendOne(s) /\ UNCHANGED counters
MCFsyncOne(s) == FsyncOne(s) /\ UNCHANGED counters
MCDeliverAck(m) == DeliverAck(m) /\ UNCHANGED counters
MCCommit(l, t) == Commit(l, t) /\ UNCHANGED counters
MCReceiveCommit(m) == ReceiveCommit(m) /\ UNCHANGED counters
MCApplyOne(s) == ApplyOne(s) /\ UNCHANGED counters
MCRestart(s) == Restart(s) /\ UNCHANGED counters

\* Fault-introducing actions: bounded.
MCTakeSnapshot(s) ==
    /\ counters.snapshot < MaxSnapshot
    /\ TakeSnapshot(s)
    /\ counters' = [counters EXCEPT !.snapshot = @ + 1]
MCCrash(s) ==
    /\ counters.crash < MaxCrash
    /\ Crash(s)
    /\ counters' = [counters EXCEPT !.crash = @ + 1]
MCDropMessage(m) ==
    /\ counters.drop < MaxDrop
    /\ DropMessage(m)
    /\ counters' = [counters EXCEPT !.drop = @ + 1]

MCNext ==
    \/ \E s \in Server : MCBeginElection(s)
    \/ \E s \in Server : MCRestartElectionRound(s)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s \in Server : MCWinElection(s)
    \/ \E s, l \in Server : MCFollowLeader(s, l)
    \/ \E s \in Server : MCStartLeading(s)
    \/ \E s \in Server : MCStartFollowing(s)
    \/ \E s \in Server : MCLeaderProposeEpoch(s)
    \/ \E s \in Server : MCAcceptEpoch(s)
    \/ \E s \in Server : MCSendAckEpoch(s)
    \/ \E s \in Server : MCLeaderPersistEpoch(s)
    \/ \E s \in Server : MCLeaderStartSync(s)
    \/ \E s \in Server : MCEnterSyncPhase(s)
    \/ \E s \in Server : MCSyncDiff(s)
    \/ \E s \in Server : MCSyncTrunc(s)
    \/ \E s \in Server : MCSyncSnap(s)
    \/ \E m \in messages : MCReceiveSyncProposal(m)
    \/ \E m \in messages : MCReceiveSyncCommit(m)
    \/ \E s \in Server : MCPersistCurrentEpoch(s)
    \/ \E s \in Server : MCClearSyncMode(s)
    \/ \E s \in Server : MCStartupWithoutServing(s)
    \/ \E s \in Server : MCLogSyncProposal(s)
    \/ \E s \in Server : MCSendNewLeaderAck(s)
    \/ \E m \in messages : MCReceiveNewLeaderAck(m)
    \/ \E s \in Server : MCStartServing(s)
    \/ \E s \in Server : MCCommitSyncPacket(s)
    \/ \E s \in Server : MCEnterBroadcast(s)
    \/ \E s \in Server : MCLeaderActivate(s)
    \/ \E s \in Server : MCLeaderEnterBroadcast(s)
    \/ \E l \in Server, t \in Txn : MCPropose(l, t)
    \/ \E m \in messages : MCReceiveProposal(m)
    \/ \E s \in Server : MCAppendOne(s)
    \/ \E s \in Server : MCFsyncOne(s)
    \/ \E m \in messages : MCDeliverAck(m)
    \/ \E l \in Server, t \in Txn : MCCommit(l, t)
    \/ \E m \in messages : MCReceiveCommit(m)
    \/ \E s \in Server : MCApplyOne(s)
    \/ \E s \in Server : MCTakeSnapshot(s)
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)
    \/ \E m \in messages : MCDropMessage(m)

MCSpec == MCInit /\ [][MCNext]_vars

MCTypeOK == counters \in [crash : 0..MaxCrash, drop : 0..MaxDrop,
                          snapshot : 0..MaxSnapshot]

\* Structural invariants (hold in every correct state of this model).
\* proposed and queued always advance together (Propose, ReceiveProposal,
\* LogSyncProposal) and are reset together (TRUNC/SNAP/Crash/Restart).
ProposedQueuedEqual == \A s \in Server : proposed[s] = queued[s]
SyncBufferOnlyInSync ==
    \A s \in Server :
        (syncBuf[s] /= <<>> \/ syncCommits[s] /= <<>>) =>
            (role[s] = "following" /\ phase[s] = "sync")
NewLeaderAckOnlyAfterEpoch ==
    \A s \in Server : nlAckSent[s] => (syncJustified[s] /\ currentEpoch[s] = acceptedEpoch[s])
StructuralInvariants == /\ ProposedQueuedEqual /\ SyncBufferOnlyInSync
                        /\ NewLeaderAckOnlyAfterEpoch

\* Bounded exploration depth for exhaustive BFS campaigns (set per cfg).
CONSTANT MaxDepth
DepthBound == TLCGet("level") <= MaxDepth

\* Reachability canaries (each is EXPECTED to be violated; a violation is a
\* witness path, never a finding).
CanaryLeaderEstablished == ~\E l \in Server : Established(l) /\ currentEpoch[l] > 0
CanaryLeaderActive == ~\E l \in Server : ActiveLeader(l)
CanaryFollowerBroadcast ==
    ~\E s \in Server : role[s] = "following" /\ phase[s] = "broadcast"
CanaryDiffAckBeforeFsync ==
    ~\E s \in Server : nlAckSent[s] /\ Len(queued[s]) > Len(durable[s])
CanaryCommittedApplied ==
    ~\E s \in Server : role[s] = "following" /\ Len(applied[s]) > 0 /\ zkState[s] = "RUNNING"
CanaryActivationCommitsOldEpoch ==
    ~\E l \in Server : /\ ActiveLeader(l) /\ Len(committed[l]) > 0
                       /\ LastEpoch(committed[l]) < currentEpoch[l]
CanaryRecovery == ~\E s \in Server : counters.crash > 0 /\ up[s] /\ Established(s)
CanarySync == ~\E s \in Server : syncMode[s] /= "NONE"
CanaryTrunc == ~\E s \in Server : syncMode[s] = "TRUNC"
CanarySnap == ~\E s \in Server : syncMode[s] = "SNAP"

=============================================================================
