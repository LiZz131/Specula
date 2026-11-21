------------------------------- MODULE MC -------------------------------
EXTENDS base

CONSTANTS n1, n2, n3,
          MaxElectionActions, MaxClientAppends, MaxMembershipChanges,
          MaxCrashes, MaxLosses

MCServer == {n1, n2, n3}

\* Ascending node-id order used by VecProgress (BTreeSet iteration).
\* UPDATE-MAP: the update made the leader commit depend on VecProgress vector
\* order (openraft/src/progress/mod.rs:80-89,222-232), so the V0 permutation
\* SYMMETRY is no longer sound and is not used by any cfg.
MCServerOrder == <<n1, n2, n3>>

\* Symmetric small membership universe: initial uniform, one-node removals,
\* and the corresponding joint transitions. Derived from next_safe:
\* openraft/src/membership/membership.rs:288-312
MCAllowedConfigs ==
    {{MCServer}}
    \union { {MCServer \ {s}} : s \in MCServer }
    \union { {MCServer, MCServer \ {s}} : s \in MCServer }

VARIABLES electionActions, clientAppends, membershipChanges, crashes, losses,
          \* Observer ghost (not implementation state): the highest commit index
          \* each node has ever reached. Crash resets the volatile `committed`
          \* (core/raft_core.rs:193-196) but not the fact that it was committed.
          commitHigh

mcCounters == <<electionActions, clientAppends, membershipChanges, crashes, losses>>
mcVars == <<vars, electionActions, clientAppends, membershipChanges, crashes, losses, commitHigh>>

\* Conjoined to every MC step: pure observation of committed'.
GhostStep == commitHigh' = [i \in Server |-> IMax(commitHigh[i], committed'[i])]

MCInit ==
    /\ Init
    /\ electionActions = 0
    /\ clientAppends = 0
    /\ membershipChanges = 0
    /\ crashes = 0
    /\ losses = 0
    /\ commitHigh = [i \in Server |-> Nil]

MCStartElection(i) ==
    /\ electionActions < MaxElectionActions
    /\ StartElection(i)
    /\ electionActions' = electionActions + 1
    /\ UNCHANGED <<clientAppends, membershipChanges, crashes, losses>>

MCClientAppend(i) ==
    /\ clientAppends < MaxClientAppends
    /\ ClientAppend(i)
    /\ clientAppends' = clientAppends + 1
    /\ UNCHANGED <<electionActions, membershipChanges, crashes, losses>>

MCProposeMembership(i, g) ==
    /\ membershipChanges < MaxMembershipChanges
    /\ ProposeMembership(i, g)
    /\ membershipChanges' = membershipChanges + 1
    /\ UNCHANGED <<electionActions, clientAppends, crashes, losses>>

MCCrash(i) ==
    /\ crashes < MaxCrashes
    /\ Crash(i)
    /\ crashes' = crashes + 1
    /\ UNCHANGED <<electionActions, clientAppends, membershipChanges, losses>>

MCLoseMessage(m) ==
    /\ losses < MaxLosses
    /\ LoseMessage(m)
    /\ losses' = losses + 1
    /\ UNCHANGED <<electionActions, clientAppends, membershipChanges, crashes>>

\* Reactive actions are intentionally unbounded; only nondeterminism-introducing
\* actions above have counters. The blank entry is a deterministic consequence
\* of winning an election (core/leader_state.rs:94-95), so it is not counted.
MCLeaderWriteBlank(i) ==
    /\ LeaderWriteBlank(i)
    /\ UNCHANGED mcCounters

MCGrantVote(i, j) ==
    /\ GrantVote(i, j)
    /\ UNCHANGED mcCounters

MCSendAppendEntries(i, j) ==
    /\ SendAppendEntries(i, j)
    /\ UNCHANGED mcCounters

MCDeliverAppendEntries(m) ==
    /\ DeliverAppendEntries(m)
    /\ UNCHANGED mcCounters

MCRejectAppendConflict(m) ==
    /\ RejectAppendConflict(m)
    /\ UNCHANGED mcCounters

MCHandleUpdateMatched(m) ==
    /\ HandleUpdateMatched(m)
    /\ UNCHANGED mcCounters

MCDiscardNegativeAck(m) ==
    /\ DiscardNegativeAck(m)
    /\ UNCHANGED mcCounters

MCRecover(i) ==
    /\ Recover(i)
    /\ UNCHANGED mcCounters

MCNextNoGhost ==
    \/ \E i \in Server: MCStartElection(i)
    \/ \E i, j \in Server: MCGrantVote(i, j)
    \/ \E i \in Server: MCLeaderWriteBlank(i)
    \/ \E i \in Server: MCClientAppend(i)
    \/ \E i \in Server, g \in Goals: MCProposeMembership(i, g)
    \/ \E i, j \in Server: MCSendAppendEntries(i, j)
    \/ \E m \in messages: MCDeliverAppendEntries(m)
    \/ \E m \in messages: MCRejectAppendConflict(m)
    \/ \E m \in messages: MCHandleUpdateMatched(m)
    \/ \E m \in messages: MCDiscardNegativeAck(m)
    \/ \E m \in messages: MCLoseMessage(m)
    \/ \E i \in Server: MCCrash(i)
    \/ \E i \in Server: MCRecover(i)

MCNext == MCNextNoGhost /\ GhostStep

MCSpec == MCInit /\ [][MCNext]_mcVars

MCTypeOK ==
    /\ TypeOK
    /\ electionActions \in 0..MaxElectionActions
    /\ clientAppends \in 0..MaxClientAppends
    /\ membershipChanges \in 0..MaxMembershipChanges
    /\ crashes \in 0..MaxCrashes
    /\ losses \in 0..MaxLosses
    /\ commitHigh \in [Server -> Index]

\* Revised OneOutstandingMembership (Case A, see spec/changelog.md): V0 used the
\* volatile `committed`, which a restart legitimately resets while the committed
\* membership is reloaded from storage. The implementation-backed requirement is
\* that a membership is promoted to committed only after the node committed it.
OneOutstandingMembershipDurable ==
    \A i \in Server:
        effectiveMembershipIndex[i] > commitHigh[i]
        => committedMembershipIndex[i] < effectiveMembershipIndex[i]

\* Keep bound counters in the fingerprint. They are experimental state even
\* though they are not implementation state; omitting them can merge paths with
\* different remaining nondeterminism budgets.
MCView == mcVars

\* The message buffer is bounded structurally; actions remain faithful.
MessageBufferBound == Cardinality(messages) <= 4

NotReachLeader == ~ReachLeader
NotReachCommitWitness == ~ReachCommitWitness
NotReachOutstandingMembership == ~ReachOutstandingMembership

=============================================================================
