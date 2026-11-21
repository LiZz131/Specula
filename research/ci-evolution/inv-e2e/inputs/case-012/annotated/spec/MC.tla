------------------------------- MODULE MC -------------------------------
EXTENDS base

CONSTANTS n1, n2, n3,
          MaxElectionActions, MaxClientAppends, MaxMembershipChanges,
          MaxCrashes, MaxLosses

MCServer == {n1, n2, n3}

\* Symmetric small membership universe: initial uniform, one-node removals,
\* and the corresponding joint transitions. Derived from next_safe:
\* openraft/src/membership/membership.rs:309-347
MCAllowedConfigs ==
    {{MCServer}}
    \union { {MCServer \ {s}} : s \in MCServer }
    \union { {MCServer, MCServer \ {s}} : s \in MCServer }

VARIABLES electionActions, clientAppends, membershipChanges, crashes, losses

mcVars == <<vars, electionActions, clientAppends, membershipChanges, crashes, losses>>

MCInit ==
    /\ Init
    /\ electionActions = 0
    /\ clientAppends = 0
    /\ membershipChanges = 0
    /\ crashes = 0
    /\ losses = 0

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

MCProposeMembership(i, cfg) ==
    /\ membershipChanges < MaxMembershipChanges
    /\ ProposeMembership(i, cfg)
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
\* actions above have counters.
MCGrantVote(i, j) ==
    /\ GrantVote(i, j)
    /\ UNCHANGED <<electionActions, clientAppends, membershipChanges, crashes, losses>>

MCSendAppendEntries(i, j) ==
    /\ SendAppendEntries(i, j)
    /\ UNCHANGED <<electionActions, clientAppends, membershipChanges, crashes, losses>>

MCDeliverAppendEntries(m) ==
    /\ DeliverAppendEntries(m)
    /\ UNCHANGED <<electionActions, clientAppends, membershipChanges, crashes, losses>>

MCRejectAppendConflict(m) ==
    /\ RejectAppendConflict(m)
    /\ UNCHANGED <<electionActions, clientAppends, membershipChanges, crashes, losses>>

MCHandleUpdateMatched(m) ==
    /\ HandleUpdateMatched(m)
    /\ UNCHANGED <<electionActions, clientAppends, membershipChanges, crashes, losses>>

MCDiscardNegativeAck(m) ==
    /\ DiscardNegativeAck(m)
    /\ UNCHANGED <<electionActions, clientAppends, membershipChanges, crashes, losses>>

MCRecover(i) ==
    /\ Recover(i)
    /\ UNCHANGED <<electionActions, clientAppends, membershipChanges, crashes, losses>>

MCNext ==
    \/ \E i \in Server: MCStartElection(i)
    \/ \E i, j \in Server: MCGrantVote(i, j)
    \/ \E i \in Server: MCClientAppend(i)
    \/ \E i \in Server, cfg \in AllowedConfigs: MCProposeMembership(i, cfg)
    \/ \E i, j \in Server: MCSendAppendEntries(i, j)
    \/ \E m \in messages: MCDeliverAppendEntries(m)
    \/ \E m \in messages: MCRejectAppendConflict(m)
    \/ \E m \in messages: MCHandleUpdateMatched(m)
    \/ \E m \in messages: MCDiscardNegativeAck(m)
    \/ \E m \in messages: MCLoseMessage(m)
    \/ \E i \in Server: MCCrash(i)
    \/ \E i \in Server: MCRecover(i)

\* REQ-EVIDENCE MCTypeOK
\* intent:   TypeOK holds and every exploration-budget counter stays within its configured bound.
\* status:   model-internal
\* watch:    none
\* verified: base
\* review:   ok
MCTypeOK ==
    /\ TypeOK
    /\ electionActions \in 0..MaxElectionActions
    /\ clientAppends \in 0..MaxClientAppends
    /\ membershipChanges \in 0..MaxMembershipChanges
    /\ crashes \in 0..MaxCrashes
    /\ losses \in 0..MaxLosses

\* Keep bound counters in the fingerprint. They are experimental state even
\* though they are not implementation state; omitting them can merge paths with
\* different remaining nondeterminism budgets.
MCView == mcVars

Symmetry == Permutations(MCServer)

\* The message buffer is bounded structurally; actions remain faithful.
MessageBufferBound == Cardinality(messages) <= 4

\* REQ-EVIDENCE NotReachLeader
\* intent:   Reachability canary (negation of ReachLeader): no node ever takes the leader role; expected to be violated, and the counterexample shows a leader is reachable.
\* status:   model-internal
\* watch:    none
\* verified: base
\* review:   ok
NotReachLeader == ~ReachLeader
\* REQ-EVIDENCE NotReachCommitWitness
\* intent:   Reachability canary (negation of ReachCommitWitness): no node ever records a commit advance; expected to be violated, and the counterexample shows a commit is reachable.
\* status:   model-internal
\* watch:    none
\* verified: base
\* review:   ok
NotReachCommitWitness == ~ReachCommitWitness
\* REQ-EVIDENCE NotReachOutstandingMembership
\* intent:   Reachability canary (negation of ReachOutstandingMembership): no node ever has an effective membership newer than its committed one; expected to be violated, and the counterexample shows an outstanding membership is reachable.
\* status:   model-internal
\* watch:    none
\* verified: base
\* review:   ok
NotReachOutstandingMembership == ~ReachOutstandingMembership

=============================================================================
