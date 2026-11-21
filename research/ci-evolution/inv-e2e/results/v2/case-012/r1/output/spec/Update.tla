------------------------------ MODULE Update ------------------------------
\* Update-focused checking lens over the V1 reference/MC suite.
\* Source update: artifact commit ce863f4 (baseline) -> aa05a38 (update).
\* Behavior is owned by base.tla / MC.tla; this module only selects MC actions,
\* defines the open environment, and states update-specific properties.
EXTENDS MC

----------------------------------------------------------------------------
\* Affected Actions: MC forms of every reference action whose semantics changed.

\* reference: base!StartElection        code: engine/engine_impl.rs:99-128, raft_state.rs:114-118
\* reference: base!GrantVote            code: engine/engine_impl.rs:163-226 (is_vote_granted), 854-912
\* reference: base!LeaderAppendEntries  code: engine/engine_impl.rs:226-292 (via ClientAppend / ProposeMembership)
\* reference: base!HandleUpdateMatched  code: core/replication.rs:97-141 -> engine/engine_impl.rs:617-647
\* reference: base!DeliverAppendEntries code: engine/engine_impl.rs:295-389 (promotion via raft_state.rs:122-136)
AffectedActions ==
    \/ \E i \in Server: MCStartElection(i)
    \/ \E i, j \in Server: MCGrantVote(i, j)
    \/ \E i \in Server: MCClientAppend(i)
    \/ \E i \in Server, cfg \in AllowedConfigs: MCProposeMembership(i, cfg)
    \/ \E m \in messages: MCHandleUpdateMatched(m)
    \/ \E m \in messages: MCDeliverAppendEntries(m)

\* Interaction Actions: unchanged producers/consumers of the changed state.
\* reference: base!SendAppendEntries    code: replication/mod.rs:264-361 (reads leader progress as cursor, carries commit)
\* reference: base!RejectAppendConflict code: engine/engine_impl.rs:322-331 (drops leader data, truncates)
InteractionActions ==
    \/ \E i, j \in Server: MCSendAppendEntries(i, j)
    \/ \E m \in messages: MCRejectAppendConflict(m)

\* Context actions omitted from the concrete focused view.
OmittedContext ==
    \/ \E m \in messages: MCDiscardNegativeAck(m)
    \/ \E m \in messages: MCLoseMessage(m)
    \/ \E i \in Server: MCCrash(i)
    \/ \E i \in Server: MCRecover(i)

FocusedNext == AffectedActions \/ InteractionActions

----------------------------------------------------------------------------
\* EnvUpdate: rely describing the omitted context's effect on update-visible
\* state. It may drop one in-flight message, or fail-stop/restart one node:
\* volatile leader data (leaderState, progress rows), commit, vote grants and the
\* commit witness may be cleared together; persistent vote/log/membership,
\* other nodes, the progress quorum set and the message pool are preserved.
\* reference: base!LoseMessage, base!DiscardNegativeAck, base!Crash, base!Recover
\* code: core/raft_core.rs:177-205 (restart rebuilds Engine with leader None)

EnvDrop ==
    /\ \E m \in messages:
          /\ messages' = messages \ {m}
          /\ \/ /\ m.type = "ack" /\ ~m.ok
                /\ losses' = losses
             \/ /\ losses < MaxLosses
                /\ losses' = losses + 1
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, role, voteGranted,
                   lastLog, logTerm, committed, matchedIndex, matchedTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   crashed, witnessIndex, witnessNodes, witnessConfig, witnessTerm,
                   leaderState, progressConfig, logConfig>>
    /\ UNCHANGED <<electionActions, clientAppends, membershipChanges, crashes>>

EnvNode(i) ==
    /\ role' = [role EXCEPT ![i] = IF i \in Voters(effectiveConfig[i])
                                     THEN "follower" ELSE "learner"]
    /\ \/ /\ i \notin crashed
          /\ crashes < MaxCrashes
          /\ crashed' = crashed \union {i}
          /\ crashes' = crashes + 1
          /\ leaderState' = [leaderState EXCEPT ![i] = FALSE]
          /\ matchedIndex' = [matchedIndex EXCEPT ![i] = NilRow]
          /\ matchedTerm' = [matchedTerm EXCEPT ![i] = ZeroRow]
          /\ committed' = [committed EXCEPT ![i] = Nil]
          /\ voteGranted' = [voteGranted EXCEPT ![i] = {}]
          /\ witnessIndex' = [witnessIndex EXCEPT ![i] = Nil]
          /\ witnessNodes' = [witnessNodes EXCEPT ![i] = {}]
          /\ witnessConfig' = [witnessConfig EXCEPT ![i] = effectiveConfig[i]]
          /\ witnessTerm' = [witnessTerm EXCEPT ![i] = 0]
       \/ /\ i \in crashed
          /\ crashed' = crashed \ {i}
          /\ crashes' = crashes
          /\ UNCHANGED <<leaderState, matchedIndex, matchedTerm, committed,
                         voteGranted, witnessIndex, witnessNodes, witnessConfig,
                         witnessTerm>>
    /\ UNCHANGED <<currentTerm, voteFor, voteCommitted, lastLog, logTerm,
                   committedConfig, effectiveConfig,
                   committedMembershipIndex, committedMembershipTerm,
                   effectiveMembershipIndex, effectiveMembershipTerm,
                   messages, progressConfig, logConfig>>
    /\ UNCHANGED <<electionActions, clientAppends, membershipChanges, losses>>

EnvUpdate ==
    \/ EnvDrop
    \/ \E i \in Server: EnvNode(i)

OpenNext == AffectedActions \/ InteractionActions \/ EnvUpdate

\* Discharge: every omitted real context step (with its MC frame) satisfies the rely.
DischargeStep == OmittedContext => EnvUpdate
DischargeContext == [][DischargeStep]_mcVars

----------------------------------------------------------------------------
\* Update-specific properties.

\* REQ-EVIDENCE CommitWitnessSound_new
\* intent:   Once a node has recorded the point its commit index last advanced to, that point stays at or below its commit index, its log still holds the committing term's entry there, the recorded supporters form a quorum of the membership used for that commit, and every recorded supporter's log still holds that entry with that term.
\* status:   mixed
\* replaces: base!CommitWitnessSound (V0), whose live clause read the leader's matched rows as a persistent per-target record
\* evidence: comment source/openraft/src/raft_state.rs:48 "a log that is replicated to a quorum of the cluster and it is of the term of the leader" -> a commit point is an entry of the leader's term replicated on a quorum
\* evidence: comment source/openraft/src/engine/engine_impl.rs:632 "Only when the log id is proposed by current leader, it is committed." -> only current-leader entries are committed by quorum counting (new in V1)
\* evidence: comment source/openraft/src/progress/mod.rs:29 "a quorum does not means committed, Raft need another condition to be satisfied: log is proposed" -> quorum acknowledgement alone is not commitment; the current-leader condition is required (new in V1)
\* evidence: doc source/raft-essentials.md:8 "has replicated it on a majority of the servers." -> a committed entry is stored on a majority
\* evidence: doc source/raft-essentials.md:103 "a server always uses the latest configuration in its log, regardless of whether the entry is committed" -> the quorum is taken in the configuration in force for that decision
\* evidence: doc source/raft-essentials.md:106 "agreement (for elections and entry commitment) requires separate majorities from both the old and new configurations" -> the quorum is a joint quorum
\* evidence: doc source/raft-essentials.md:79 "a leader never overwrites or deletes entries in its own log." -> the committed entry stays in the leader's log
\* evidence: doc source/raft-essentials.md:84 "(which will only ever happen to uncommitted log entries)" -> a committed entry is never overwritten on the servers that store it
\* evidence: impl source/openraft/src/engine/engine_impl.rs:629 "*leader.progress.update(&node_id, log_id)"
\* evidence: impl source/openraft/src/raft_state.rs:123 "if committed > &self.committed {"
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::update_progress; source/openraft/src/engine/engine_impl.rs:Engine::leader_append_entries; source/openraft/src/engine/engine_impl.rs:Engine::update_effective_membership; source/openraft/src/progress/mod.rs:VecProgress::update; source/openraft/src/progress/mod.rs:VecProgress::upgrade_quorum_set; source/openraft/src/raft_state.rs:RaftState::update_committed; source/openraft/src/raft_state.rs:RaftState::new_leader; source/openraft/src/core/replication.rs:LeaderState::handle_update_matched
\* verified: update (aa05a38)
\* clause commit-not-below-witness: requirement — witnessIndex <= committed; raft_state.rs:123 is impl, but V0 ledger's history quote (commit never below its previous value) is retained; kept unchanged from V0
\* clause entry-retained: requirement — witnessIndex <= lastLog and the local entry term equals witnessTerm; raft-essentials.md:79/:84
\* clause quorum-support: requirement — Quorum(witnessConfig, witnessNodes); raft_state.rs:48, raft-essentials.md:8/:103/:106, engine_impl.rs:632
\* clause supporters-retain-entry: requirement — each supporter's log holds the entry with witnessTerm; raft-essentials.md:8 and :84 (replicated on a majority; committed entries are never overwritten)
\* clause witness-bookkeeping: model-internal — witness* are observer variables
\* note:     the V0 clause "every witness node's matchedIndex/matchedTerm still reaches the witness" (V0 status: quorum-support requirement + matched-term-kept unknown) is removed because V1 progress rows are recreated by RaftState::new_leader (raft_state.rs:116-118) and re-keyed by upgrade_quorum_set (progress/mod.rs:222-232); progress/mod.rs:4 "Decreasing it is not allowed" constrains one progress instance and is checked separately by ProgressMonotonic. The replacement clause reads the supporters' actual logs.
CommitWitnessSound_new ==
    \A i \in Server:
        witnessIndex[i] = Nil
        \/ /\ witnessIndex[i] <= committed[i]
           /\ witnessIndex[i] <= lastLog[i]
           /\ witnessTerm[i] = logTerm[i][witnessIndex[i]]
           /\ Quorum(witnessConfig[i], witnessNodes[i])
           /\ \A j \in witnessNodes[i]:
                 /\ lastLog[j] >= witnessIndex[i]
                 /\ logTerm[j][witnessIndex[i]] = witnessTerm[i]

\* REQ-EVIDENCE LeaderProgressConfigCurrent
\* intent:   Whenever a node holds leader (candidate or leader) data, the quorum set of its leader progress, which decides both vote and commit quorums, equals its effective membership.
\* status:   requirement
\* evidence: comment source/openraft/src/engine/engine_impl.rs:601 "If membership changes, the progress should be upgraded." -> every effective-membership change must be reflected in the leader progress quorum set
\* evidence: comment source/openraft/src/engine/engine_impl.rs:282 "since this entry, the condition to commit has been changed." -> commit conditions follow the newest membership entry
\* evidence: doc source/raft-essentials.md:103 "it uses that configuration for all future decisions (a server always uses the latest configuration in its log, regardless of whether the entry is committed)" -> vote and commit quorums use the latest (effective) configuration
\* evidence: test source/openraft/src/engine/update_effective_membership_test.rs:128 test_update_effective_membership_for_leader "eng.state.leader.unwrap().progress.get(&4).is_none()" -> after an effective change the leader progress tracks the new member set
\* evidence: impl source/openraft/src/raft_state.rs:117 "self.leader = Some(Leader::new(self.membership_state.effective.clone()));"
\* evidence: impl source/openraft/src/engine/engine_impl.rs:603 "leader.progress = leader.progress.clone().upgrade_quorum_set(em);"
\* watch:    source/openraft/src/raft_state.rs:RaftState::new_leader; source/openraft/src/engine/engine_impl.rs:Engine::update_effective_membership; source/openraft/src/engine/engine_impl.rs:Engine::truncate_logs; source/openraft/src/engine/engine_impl.rs:Engine::follower_update_membership; source/openraft/src/engine/engine_impl.rs:Engine::update_committed_membership; source/openraft/src/engine/engine_impl.rs:Engine::internal_handle_vote_req; source/openraft/src/leader/leader.rs:Leader::is_vote_granted
\* verified: update (aa05a38)
\* note:     the modeled scope does not contain RaftCore paths that change the vote/role without clearing Engine leader data (replication.rs handle_revert_to_follower, install_snapshot.rs:49-55); they are outside the MC Next relation and recorded as a coverage limit.
LeaderProgressConfigCurrent ==
    \A i \in Server: leaderState[i] => progressConfig[i] = effectiveConfig[i]

\* REQ-EVIDENCE ProgressMonotonic
\* intent:   Within one leader-data lifetime (same term, leader data present before and after), the progress value of an id tracked before and after a step never decreases in LogId order.
\* status:   requirement
\* evidence: doc source/openraft/src/progress/mod.rs:4 "The scalar value is monotonically incremental. Decreasing it is not allowed." -> a tracked progress value never decreases
\* evidence: comment source/openraft/src/core/replication.rs:122 "the matched increments monotonically" -> acknowledged matched values only grow
\* evidence: impl source/openraft/src/progress/mod.rs:180 "debug_assert!(value > prev);"
\* watch:    source/openraft/src/progress/mod.rs:VecProgress::update; source/openraft/src/progress/mod.rs:VecProgress::upgrade_quorum_set; source/openraft/src/engine/engine_impl.rs:Engine::update_progress; source/openraft/src/engine/engine_impl.rs:Engine::leader_append_entries; source/openraft/src/core/replication.rs:LeaderState::handle_update_matched
\* verified: update (aa05a38)
ProgressMonotonicStep ==
    \A i, j \in Server:
        (/\ leaderState[i]
         /\ leaderState'[i]
         /\ currentTerm'[i] = currentTerm[i]
         /\ j \in Voters(progressConfig[i])
         /\ j \in Voters(progressConfig'[i]))
        => LidGeq(RowLid(matchedIndex'[i], matchedTerm'[i], j),
                  RowLid(matchedIndex[i], matchedTerm[i], j))
ProgressMonotonic == [][ProgressMonotonicStep]_mcVars

----------------------------------------------------------------------------
\* Update Scenario canaries (expected violations are reachability witnesses).

\* U-S1 (leader append under membership upgrade commits using follower progress).
\* REQ-EVIDENCE NoCommitAtLeaderAppend
\* intent:   Reachability canary (action form): no step both appends to a leader's log and advances its commit; expected to be violated.
\* status:   model-internal
\* watch:    none
\* verified: update (aa05a38)
NoCommitAtLeaderAppendStep ==
    ~(\E i \in Server: /\ role[i] = "leader"
                       /\ lastLog'[i] > lastLog[i]
                       /\ committed'[i] > committed[i])
NoCommitAtLeaderAppend == [][NoCommitAtLeaderAppendStep]_mcVars

\* U-S2 (re-election recreates leader progress while an old witness exists).
NotReachReelectedWitness == NotReachReelectedLeaderWithOldWitness

\* U-S3 (follower promotion only on commit advance).
NotReachUnpromoted == NotReachUnpromotedCoveredMembership

\* U-S4 (progress quorum set upgraded by a membership entry).
NotReachProgressUpgrade == NotReachLeaderWithProgressUpgrade

\* Evidence-only canaries (keep evidence for ElectionSafety / CommittedLogAgreement
\* needs states whose quantified records are nonempty).
NotReachTwoLeaders ==
    ~(\E i, j \in Server: i # j /\ role[i] = "leader" /\ role[j] = "leader")
NotReachTwoCommitted ==
    ~(\E i, j \in Server: i # j /\ committed[i] # Nil /\ committed[j] # Nil
                          /\ witnessIndex[i] # Nil)

=============================================================================
