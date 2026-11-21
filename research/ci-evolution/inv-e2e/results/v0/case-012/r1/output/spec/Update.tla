------------------------------ MODULE Update ------------------------------
\* Update-focused checking view over the complete MC/reference suite.
\* Source delta: baseline ce863f4 -> update aa05a38 (OpenRaft 0.6.4 tree).
\* Mechanism: leader commit moved from LeaderState::calc_commit_log_id
\* (greatest_majority_value over all matched values, recomputed on every ack)
\* to Engine::update_progress over a leader-owned VecProgress whose cached
\* `committed` is recomputed only when an updated value crosses it, and whose
\* quorum set is rebuilt by upgrade_quorum_set on every effective-membership
\* change. No action body is duplicated here: every behavior is owned by
\* base.tla / MC.tla.
EXTENDS MC

\* ---------------------------------------------------------------------------
\* Affected Actions: MC forms of every directly changed reference Action.
\* ---------------------------------------------------------------------------
AffectedActions ==
    \* reference: base!StartElection   code: engine_impl.rs:100-131 (new_leader, is_vote_granted)
    \/ \E i \in Server: MCStartElection(i)
    \* reference: base!GrantVote       code: engine_impl.rs:167-224, 854-912
    \/ \E i, j \in Server: MCGrantVote(i, j)
    \* reference: base!LeaderWriteBlank / base!LeaderAppendEntries
    \* code: engine_impl.rs:234-290 (update_progress + update_effective_membership)
    \/ \E i \in Server: MCLeaderWriteBlank(i)
    \/ \E i \in Server: MCClientAppend(i)
    \/ \E i \in Server, g \in Goals: MCProposeMembership(i, g)
    \* reference: base!HandleUpdateMatched  code: core/replication.rs:96-141
    \/ \E m \in messages: MCHandleUpdateMatched(m)
    \* reference: base!DeliverAppendEntries code: engine_impl.rs:363-386 (update_committed)
    \/ \E m \in messages: MCDeliverAppendEntries(m)

\* ---------------------------------------------------------------------------
\* Interaction Actions: unchanged producers / fault boundaries that matter.
\* ---------------------------------------------------------------------------
InteractionActions ==
    \* producer of the acknowledgements consumed by HandleUpdateMatched
    \* reference: base!SendAppendEntries code: replication/mod.rs:264-361
    \/ \E i, j \in Server: MCSendAppendEntries(i, j)
    \* crash clears the volatile Leader/VecProgress and commit
    \* reference: base!Crash code: core/raft_core.rs:181-205
    \/ \E i \in Server: MCCrash(i)

\* Real context Actions omitted from the concrete focus.
OmittedContext ==
    \/ \E m \in messages: MCRejectAppendConflict(m)
    \/ \E m \in messages: MCDiscardNegativeAck(m)
    \/ \E m \in messages: MCLoseMessage(m)
    \/ \E i \in Server: MCRecover(i)

\* ---------------------------------------------------------------------------
\* EnvUpdate: rely for the omitted context, restricted to update-visible effects.
\* The omitted Actions may (a) remove an in-flight message, (b) bring a crashed
\* node back without leader state, or (c) make an append receiver adopt the
\* sender's term, drop its own Leader/VecProgress, truncate only an uncommitted
\* log suffix and answer with a negative ack. They never touch another node's
\* VecProgress, commit, matched values, or membership.
\* ---------------------------------------------------------------------------
progressFrame == <<leaderSome, progVec, progCommitted, progQS, blankPending>>

EnvDropMessage ==
    \E m \in messages:
        /\ messages' = messages \ {m}
        /\ losses' \in {losses, losses + 1}
        /\ losses' <= MaxLosses
        /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, role, voteGranted,
                       lastLog, logTerm, committed, matchedIndex, matchedTerm,
                       committedConfig, effectiveConfig,
                       committedMembershipIndex, committedMembershipTerm,
                       effectiveMembershipIndex, effectiveMembershipTerm,
                       crashed, witnessIndex, witnessNodes, witnessConfig, witnessTerm,
                       progressFrame,
                       electionActions, clientAppends, membershipChanges, crashes>>

EnvRecover ==
    \E i \in crashed:
        /\ crashed' = crashed \ {i}
        /\ role' = [role EXCEPT ![i] = IF i \in Voters(effectiveConfig[i])
                                         THEN "follower" ELSE "learner"]
        /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, voteGranted,
                       lastLog, logTerm, committed, matchedIndex, matchedTerm,
                       committedConfig, effectiveConfig,
                       committedMembershipIndex, committedMembershipTerm,
                       effectiveMembershipIndex, effectiveMembershipTerm,
                       messages, witnessIndex, witnessNodes, witnessConfig, witnessTerm,
                       progressFrame, mcCounters>>

EnvFollowerConflict ==
    \E m \in messages:
      LET j == m.to IN
      /\ m.type = "append"
      /\ j \notin crashed
      /\ m.term >= currentTerm[j]
      /\ \E newLast \in IMax(committed[j], Nil)..IMax(lastLog[j], committed[j]):
            /\ lastLog' = [lastLog EXCEPT ![j] = newLast]
            /\ logTerm' = [logTerm EXCEPT ![j] =
                              [k \in 0..MaxIndex |-> IF k > newLast THEN 0 ELSE logTerm[j][k]]]
      /\ currentTerm' = [currentTerm EXCEPT ![j] = m.term]
      /\ voteFor' = [voteFor EXCEPT ![j] = m.from]
      /\ voteCommitted' = [voteCommitted EXCEPT ![j] = TRUE]
      /\ role' = [role EXCEPT ![j] = IF j \in Voters(effectiveConfig[j])
                                       THEN "follower" ELSE "learner"]
      /\ voteGranted' = [voteGranted EXCEPT ![j] = {}]
      /\ leaderSome' = [leaderSome EXCEPT ![j] = FALSE]
      /\ progVec' = [progVec EXCEPT ![j] = <<>>]
      /\ progCommitted' = [progCommitted EXCEPT ![j] = 0]
      /\ progQS' = [progQS EXCEPT ![j] = NoQS]
      /\ blankPending' = [blankPending EXCEPT ![j] = FALSE]
      /\ messages' = (messages \ {m}) \union
                        {[type |-> "ack", from |-> j, to |-> m.from,
                          term |-> m.term, prev |-> m.prev, last |-> m.prev,
                          lastTerm |-> 0, leaderCommit |-> committed[j], ok |-> FALSE]}
      /\ UNCHANGED <<committed, matchedIndex, matchedTerm,
                     committedConfig, effectiveConfig,
                     committedMembershipIndex, committedMembershipTerm,
                     effectiveMembershipIndex, effectiveMembershipTerm,
                     crashed, witnessIndex, witnessNodes, witnessConfig, witnessTerm,
                     mcCounters>>

EnvUpdate == EnvDropMessage \/ EnvRecover \/ EnvFollowerConflict

FocusedNext == (AffectedActions \/ InteractionActions) /\ GhostStep
OpenUpdateNext == (AffectedActions \/ InteractionActions \/ EnvUpdate) /\ GhostStep

FocusedSpec == MCInit /\ [][FocusedNext]_mcVars
OpenSpec == MCInit /\ [][OpenUpdateNext]_mcVars

\* Discharge: every omitted real context step satisfies the rely (frame included).
DischargeContext == [][OmittedContext => EnvUpdate]_mcVars

\* ---------------------------------------------------------------------------
\* Update-specific properties.
\* ---------------------------------------------------------------------------
ValsAtLeast(i, v) == {progVec[i][k].id : k \in {k2 \in DOMAIN progVec[i] : progVec[i][k2].val >= v}}

\* Scenario U1. VecProgress' cached committed value is a value acknowledged by a
\* quorum of its own quorum set: progress/mod.rs:52-53 ("Currently already
\* committed value") and the update() contract "find the max value that has
\* constituted a quorum" (progress/mod.rs:186). Revised replacement of V0's
\* implicit greatest_majority_value guarantee (membership.rs, removed).
ProgressCommittedSound ==
    \A i \in Server:
        (leaderSome[i] /\ progCommitted[i] # 0)
        => Quorum(progQS[i], ValsAtLeast(i, progCommitted[i]))

\* Scenario U1 (structural). Representation invariant documented on the
\* VecProgress vector field: "Elements with values greater than the committed
\* are sorted in descending order" (progress/mod.rs:56-58). The scan in
\* update() relies on it to read vector[i] as the minimum of vector[0..=i].
ProgressSortedAboveCommitted ==
    \A i \in Server:
        leaderSome[i] =>
            \A k \in 1..(Len(progVec[i]) - 1):
                progVec[i][k + 1].val > progCommitted[i]
                => progVec[i][k].val >= progVec[i][k + 1].val

\* Scenario U2 (interaction). Leader progress never exceeds what the leader
\* actually knows to be replicated: its own appended log (engine_impl.rs:285-287)
\* and the replication-state matched value of each target (replication.rs:126).
ProgressWithinReplication ==
    \A i \in Server:
        (leaderSome[i] /\ role[i] = "leader") =>
            \A k \in DOMAIN progVec[i]:
                LET j == progVec[i][k].id
                IN progVec[i][k].val <= LV(matchedTerm[i][j], matchedIndex[i][j])

\* Scenario U3 (interaction). The progress quorum set follows the effective
\* membership: created from it by new_leader (raft_state.rs:114-117) and
\* upgraded by update_effective_membership (engine_impl.rs:602-604). Vote
\* quorums (leader.rs:49-53) and commit quorums both read this quorum set.
ProgressTracksEffective ==
    \A i \in Server: leaderSome[i] => progQS[i] = effectiveConfig[i]

\* Update scenarios also re-enable the externally meaningful reference
\* properties CommitWitnessSound, CommittedLogAgreement, OneOutstandingMembership.

\* ---------------------------------------------------------------------------
\* Reachability canaries (expected to be violated: each counterexample is a
\* witness that the update interaction is reachable in the checked model).
\* ---------------------------------------------------------------------------
\* A leader whose own progress entry is not at the head of its vector.
NotReachLeaderNotFirst ==
    ~\E i \in Server:
        /\ role[i] = "leader"
        /\ \E k \in DOMAIN progVec[i]:
              k > 1 /\ progVec[i][k].id = i /\ progVec[i][k].val > 0

\* A leader whose progress was upgraded to a joint quorum set while carrying
\* a follower's acknowledged value.
NotReachUpgradedWithFollowerProgress ==
    ~\E i \in Server:
        /\ role[i] = "leader"
        /\ Cardinality(progQS[i]) = 2
        /\ \E k \in DOMAIN progVec[i]: progVec[i][k].id # i /\ progVec[i][k].val > 0

\* A commit decision taken by the progress under a joint quorum set.
NotReachJointQuorumCommit ==
    ~\E i \in Server:
        /\ witnessIndex[i] # Nil
        /\ Cardinality(witnessConfig[i]) = 2

\* Scenario U4: a leader of a later term (after re-election) whose fresh
\* progress has recorded a follower acknowledgement.
NotReachReelectedLeaderProgress ==
    ~\E i \in Server:
        /\ role[i] = "leader"
        /\ currentTerm[i] >= 2
        /\ \E k \in DOMAIN progVec[i]: progVec[i][k].id # i /\ progVec[i][k].val > 0

\* A leader that committed through progress at all.
NotReachProgressCommit ==
    ~\E i \in Server: role[i] = "leader" /\ committed[i] # Nil /\ witnessIndex[i] # Nil

=============================================================================
