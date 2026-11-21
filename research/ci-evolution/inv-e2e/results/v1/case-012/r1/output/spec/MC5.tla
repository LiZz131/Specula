------------------------------- MODULE MC5 ------------------------------
EXTENDS base

CONSTANTS n1, n2, n3, n4, n5,
          MaxElectionActions, MaxClientAppends, MaxMembershipChanges,
          MaxCrashes, MaxLosses

\* 5-server instantiation of the MC wrappers (checking harness only; behaviour is
\* owned by base).  Initial voters {n1,n2,n3}; n4, n5 start as learners.
MCServer == {n1, n2, n3, n4, n5}
MC5Voters == {n1, n2, n3}
MC5InitialConfig == {MC5Voters}

\* Node-id order n1 < n2 < n3.  The updated VecProgress initial vector and
\* upgrade replay follow BTreeSet id order (progress/mod.rs:81-89,222-232), so
\* the V0 SYMMETRY reduction is no longer sound and is removed from every cfg.
\* UPDATE-MAP
\* code: openraft/src/progress/mod.rs:81-89,222-232
\* update: Update!AffectedActions
MCServerOrder == <<n1, n2, n3, n4, n5>>

\* Small membership universe: initial uniform, one-node removals, and the joint
\* configurations next_safe produces between them.
\* openraft/src/membership/membership.rs:288-309
MCAllowedConfigs ==
    {{MC5Voters}, {MC5Voters, MCServer}, {MCServer}}

VARIABLES electionActions, clientAppends, membershipChanges, crashes, losses

counterVars == <<electionActions, clientAppends, membershipChanges, crashes, losses>>
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
    /\ UNCHANGED counterVars

MCSendAppendEntries(i, j) ==
    /\ SendAppendEntries(i, j)
    /\ UNCHANGED counterVars

MCDeliverAppendEntries(m) ==
    /\ DeliverAppendEntries(m)
    /\ UNCHANGED counterVars

MCRejectAppendConflict(m) ==
    /\ RejectAppendConflict(m)
    /\ UNCHANGED counterVars

MCHandleUpdateMatched(m) ==
    /\ HandleUpdateMatched(m)
    /\ UNCHANGED counterVars

MCDiscardNegativeAck(m) ==
    /\ DiscardNegativeAck(m)
    /\ UNCHANGED counterVars

MCRecover(i) ==
    /\ Recover(i)
    /\ UNCHANGED counterVars

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

MCSpec == MCInit /\ [][MCNext]_mcVars

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

\* The message buffer is bounded structurally; actions remain faithful.
MessageBufferBound == Cardinality(messages) <= 4

NotReachLeader == ~ReachLeader
NotReachCommitWitness == ~ReachCommitWitness
NotReachOutstandingMembership == ~ReachOutstandingMembership

\* Directed exploration for update Scenario U1-divergence (restricts the search
\* only; every explored step is an unchanged MCNext step): only n1/n2 elect,
\* only n2 may crash, n5 stays idle, and n2 replicates only to n1/n4.
DirectedU1 ==
    /\ \A i \in {n3, n4, n5}: role'[i] # "candidate"
    /\ crashed' \subseteq {n2}
    /\ \A m \in messages' \ messages:
          /\ m.to # n5 /\ m.from # n5
          /\ (m.type = "append" /\ m.from = n2) => m.to \in {n1, n4}
          /\ (m.type = "append" /\ m.from = n1) => m.to = n3

=============================================================================
