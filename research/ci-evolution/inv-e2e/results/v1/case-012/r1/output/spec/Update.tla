------------------------------ MODULE Update ------------------------------
\* Update-focused checking lens over the complete updated reference (base/MC).
\* It owns no behaviour: every Action below is an MC wrapper of base.
\* Source delta: baseline ce863f4 -> update aa05a38 (synthetic neutral commits).
EXTENDS MC

\* ---------------------------------------------------------------------------
\* Affected Actions (reference Actions whose semantics changed)
\* ---------------------------------------------------------------------------

\* reference: base!LeaderAppendEntries via base!ClientAppend
\* code: openraft/src/engine/engine_impl.rs:236-293 (leader_append_entries -> update_progress)
ClientAppendFocus == \E i \in Server: MCClientAppend(i)

\* reference: base!LeaderAppendEntries via base!ProposeMembership,
\*            base!UpgradeQuorumSet, base!SafeNext
\* code: openraft/src/engine/engine_impl.rs:270-288, 591-615;
\*       openraft/src/progress/mod.rs:222-232; openraft/src/core/admin.rs:146-201
ProposeMembershipFocus == \E i \in Server, cfg \in AllowedConfigs: MCProposeMembership(i, cfg)

\* reference: base!HandleUpdateMatched, base!UpdateProgressResult, base!VecUpdate
\* code: openraft/src/core/replication.rs:92-141; engine/engine_impl.rs:617-647;
\*       openraft/src/progress/mod.rs:163-207
HandleUpdateMatchedFocus == \E m \in messages: MCHandleUpdateMatched(m)

\* reference: base!StartElection (new_leader + progress quorum set), base!GrantVote
\* code: openraft/src/engine/engine_impl.rs:100-130,163-227; leader/leader.rs:37-53
ElectionFocus ==
    \/ \E i \in Server: MCStartElection(i)
    \/ \E i, j \in Server: MCGrantVote(i, j)

\* reference: base!DeliverAppendEntries (promotion only on commit advance,
\*            Engine leader state cleared)
\* code: openraft/src/engine/engine_impl.rs:363-386; raft_state.rs:122-137
FollowerFocus == \E m \in messages: MCDeliverAppendEntries(m)

AffectedActions ==
    \/ ClientAppendFocus
    \/ ProposeMembershipFocus
    \/ HandleUpdateMatchedFocus
    \/ ElectionFocus
    \/ FollowerFocus

\* ---------------------------------------------------------------------------
\* Interaction Actions (unchanged producers/consumers of the changed state)
\* ---------------------------------------------------------------------------
\* SendAppendEntries produces the acknowledgements consumed by
\* HandleUpdateMatched and carries the leader commit to followers.
\* reference: base!SendAppendEntries; code: openraft/src/replication/mod.rs:264-361
InteractionActions ==
    \E i, j \in Server: MCSendAppendEntries(i, j)

\* Concrete focused model: the leader commit pipeline only.
ConcreteFocusNext ==
    \/ AffectedActions
    \/ InteractionActions

ConcreteFocusSpec == MCInit /\ [][ConcreteFocusNext]_mcVars

\* ---------------------------------------------------------------------------
\* Omitted context and its environment (open spec)
\* ---------------------------------------------------------------------------
\* Omitted real context actions (MC forms).  RejectAppendConflict and Crash
\* also changed (they now clear Engine leader state); they are handled through
\* the environment here and concretely in the full MCNext check.
OmittedContext ==
    \/ \E m \in messages: MCRejectAppendConflict(m)
    \/ \E m \in messages: MCDiscardNegativeAck(m)
    \/ \E m \in messages: MCLoseMessage(m)
    \/ \E i \in Server: MCCrash(i)
    \/ \E i \in Server: MCRecover(i)

\* EnvUpdate: the omitted context without its MC budgets (unbounded faults).
\* DiscardNegativeAck is subsumed by message loss.  This is constructive so the
\* open spec can be explored; its tolerated effect is stated by EnvRely.
EnvEffect ==
    \/ \E m \in messages: LoseMessage(m)
    \/ \E m \in messages: RejectAppendConflict(m)
    \/ \E i \in Server: Crash(i)
    \/ \E i \in Server: Recover(i)

EnvUpdate ==
    /\ UNCHANGED counterVars
    /\ EnvEffect

\* Frame for MC-private budget counters: omitted context may only consume fault
\* budgets; it never touches election/append/membership budgets.
CounterFrame ==
    /\ UNCHANGED <<electionActions, clientAppends, membershipChanges>>
    /\ crashes' >= crashes
    /\ losses' >= losses

\* Rely: the environment never creates or advances leader progress, never raises
\* a commit index, never produces positive acknowledgements or append requests,
\* never changes terms except by adopting a received append's term, and never
\* changes membership.
EnvRely ==
    /\ \A i \in Server:
          /\ leaderActive'[i] => (leaderActive[i] /\ progress'[i] = progress[i])
          /\ committed'[i] # committed[i] => committed'[i] = Nil
          /\ witnessIndex'[i] # witnessIndex[i] => witnessIndex'[i] = Nil
          /\ currentTerm'[i] >= currentTerm[i]
          /\ effectiveConfig'[i] = effectiveConfig[i]
          /\ effectiveMembershipIndex'[i] = effectiveMembershipIndex[i]
          /\ committedMembershipIndex'[i] = committedMembershipIndex[i]
    /\ \A m \in messages' \ messages: m.type = "ack" /\ ~m.ok

OpenUpdateNext ==
    \/ AffectedActions
    \/ InteractionActions
    \/ EnvUpdate

OpenUpdateSpec == MCInit /\ [][OpenUpdateNext]_mcVars

\* Checked on the open spec: every environment step satisfies the rely.
EnvRelyHolds == [][EnvUpdate => EnvRely]_mcVars

\* Discharge: every omitted real context step (full MCNext) is an EnvUpdate step.
\* (Budget counters are MC-private: the obligation is EnvEffect on protocol state
\*  plus CounterFrame on the counters.)
DischargeContext == [][OmittedContext => (EnvEffect /\ CounterFrame)]_mcVars

\* ---------------------------------------------------------------------------
\* Update-specific properties
\* ---------------------------------------------------------------------------

ActiveLeaders == {i \in Server : leaderActive[i]}

\* (added) The VecProgress committed value is supported by a quorum of the
\* progress values (ids with value >= committed form a quorum).
\* Requirement: progress/mod.rs:15-16 ("calculates the committed value through a
\* QuorumSet"); progress/mod.rs:188 ("find the max value that has constituted a
\* quorum"); progress/mod.rs:195 ("Ids of the target that has value GE
\* vector[i]"); test vec_progress_update assertions (progress/mod.rs:274-298).
\* Scenario U1.
ProgressCommittedSupported ==
    \A i \in ActiveLeaders:
        progress[i].committed = NoLog \/ QuorumAt(progress[i], progress[i].committed)

\* (added) Exactness diagnostic: committed is the greatest quorum value.
\* Requirement: same citations; vec_progress_upgrade_quorum_set asserts the
\* committed value falls back/advances to the quorum value after an upgrade
\* (progress/mod.rs:300-338).  Scenario U1/U2.
ProgressCommittedGreatest ==
    \A i \in ActiveLeaders:
        \A j \in SeqElems(progress[i].order):
            LET v == progress[i].val[j]
            IN QuorumAt(progress[i], v) => LogLE(v, progress[i].committed)

\* (added, structural) The documented VecProgress representation invariant:
\* "Elements with values greater than the committed are sorted in descending
\* order" (progress/mod.rs:54-57).  The recompute loop relies on it.
\* Scenario U1.
ProgressSortedAboveCommitted ==
    \A i \in ActiveLeaders:
        LET p == progress[i]
        IN \A a, b \in 1..Len(p.order):
              (a < b /\ LogLT(p.committed, p.val[p.order[a]])
                     /\ LogLT(p.committed, p.val[p.order[b]]))
              => ~LogLT(p.val[p.order[a]], p.val[p.order[b]])

\* (added, interaction) Leader progress never exceeds what the replication
\* stream actually acknowledged (followers) or what the leader appended (self).
\* Scenario U1/U2.
ProgressWithinAcks ==
    \A i \in ActiveLeaders:
        \A j \in SeqElems(progress[i].order):
            LET v == progress[i].val[j]
            IN v = NoLog
               \/ IF j = i
                  THEN v[2] <= lastLog[i] /\ v[1] = logTerm[i][v[2]]
                  ELSE /\ v[2] <= matchedIndex[i][j]
                       /\ v[1] <= matchedTerm[i][j]

\* Revised in meaning: CommitWitnessSound (base) is unchanged text, but the
\* witness is now computed from ground-truth acknowledgements independently of
\* the VecProgress commit computation.  The V0 witness was derived from the same
\* values that produced the commit.  Alias for update cfgs:
UpdCommitWitnessSound == CommitWitnessSound

\* ---------------------------------------------------------------------------
\* Reachability canaries (expected to be violated: each counterexample is a
\* witness that the update interaction is reachable)
\* ---------------------------------------------------------------------------
\* A leader commit backed by a joint (two-group) membership witness.
NotReachJointCommit ==
    ~\E i \in Server: witnessIndex[i] # Nil /\ Cardinality(witnessConfig[i]) = 2
\* An active leader progress whose quorum set was upgraded to a joint config.
NotReachUpgradedProgress ==
    ~\E i \in ActiveLeaders: Cardinality(progress[i].cfg) = 2
\* A leader progress with at least two values above its committed value
\* (the precondition of an order-sensitive recompute).
NotReachTwoAboveCommitted ==
    ~\E i \in ActiveLeaders:
        Cardinality({j \in SeqElems(progress[i].order):
                        LogLT(progress[i].committed, progress[i].val[j])}) >= 2
\* Leader commit advanced by update_progress in the leader's term.
NotReachLeaderProgressCommit ==
    ~\E i \in Server: role[i] = "leader" /\ committed[i] # Nil /\ witnessIndex[i] # Nil
\* A candidate wins through vote counting on its progress quorum set.
NotReachElectedByVotes ==
    ~\E i \in Server: role[i] = "leader" /\ voteGranted[i] # {i}
\* A follower's committed membership promoted on commit advance.
NotReachFollowerPromotion ==
    ~\E i \in Server: role[i] = "follower" /\ committedMembershipIndex[i] # Nil

=============================================================================
