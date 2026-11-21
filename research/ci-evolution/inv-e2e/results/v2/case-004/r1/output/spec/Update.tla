---- MODULE Update ----
(***************************************************************************)
(* Update-focused checking lens for artifact commit d7176ef ("update"):    *)
(* RaftMsg::TransferLeader{from,to} (core/raft_core.rs:1190-1202), its     *)
(* producer Raft::transfer_leader (raft/mod.rs:635-703) and the lease      *)
(* switch in utime.rs. All behavior is owned by base.tla / MC.tla; this    *)
(* module only selects actions and states update properties.               *)
(***************************************************************************)

EXTENDS MC

(***************************************************************************)
(* Affected Actions                                                        *)
(* reference: base!TransferLeader (-> base!Elect); MC!MCTransferLeader     *)
(* code: openraft/src/core/raft_core.rs:1190-1202                          *)
(***************************************************************************)

AffectedActions ==
    \E n \in Server : MCTransferLeader(n)

(***************************************************************************)
(* Interaction Actions (update Scenarios U1-U4 in modeling-brief.md).      *)
(*  producer/precondition: leader election and follower append give the   *)
(*      target a committed leader vote (vote == from);                     *)
(*  consumers: SaveVote/SendVote, peers' VoteRequest handling (log         *)
(*      freshness, engine_impl.rs:318), VoteResponse/establish_leader,     *)
(*      replication/commit by the new leader, client append;               *)
(*  membership: learner add / joint (who is a voter when the message      *)
(*      arrives);                                                          *)
(*  faults: crash/restart around the transfer election.                    *)
(***************************************************************************)

InteractionActions ==
    \/ \E n \in ElectNodes : MCElect(n)
    \/ \E n \in Server : MCPersistVote(n) \/ MCSendVote(n)
    \/ \E n, c \in Server : MCVoteRequest(n, c)
    \/ \E n, p \in Server : MCVoteResponse(n, p)
    \/ \E n \in Server : MCDataAppend(n) \/ MCAddLearner(n) \/ MCJoint(n)
                         \/ MCUniform(n)
    \/ \E n, l \in Server : MCFollowerAppend(n, l)
    \/ \E n \in Server : MCSubmit(n) \/ MCFlush(n) \/ MCRespond(n)
                         \/ MCSaveCommit(n)
    \/ \E n, p \in Server : MCAck(n, p)
    \/ \E n \in Server : MCCrash(n) \/ MCRestart(n)

\* Reference actions omitted from the concrete focused spec.
OmittedContextActions ==
    \/ \E n \in Server : MCApply(n)
    \/ \E n, p \in Server : MCStale(n, p)

FocusedNext == AffectedActions \/ InteractionActions
FocusedSpec == MCInit /\ [][FocusedNext]_MCVars

(***************************************************************************)
(* Open focused spec. The omitted actions write only appliedIndex,         *)
(* staleResponseSeen, commands and staleCount; none of these is read by an *)
(* affected/interaction guard or by an update property. EnvUpdate states   *)
(* exactly that rely: every update-visible variable is preserved.          *)
(***************************************************************************)

HiddenVars == <<appliedIndex, staleResponseSeen, commands, staleCount>>
UpdateVisibleVars ==
    <<up, panicked, voteVars, logs, commitIndex, acceptedIndex, submittedIndex,
      flushedIndex, durableLogs, durableCommit, membershipVars, electionVars,
      match, electionCount, transferCount, appendCount, membershipCount,
      crashCount, grantLog, voteReqs, transferLog>>

EnvUpdate ==
    /\ UNCHANGED UpdateVisibleVars
    /\ \E n \in Server :
         /\ commands' = [commands EXCEPT ![n] = {}]
         /\ appliedIndex' \in {appliedIndex,
                               [appliedIndex EXCEPT ![n] = durableCommit[n]]}
    /\ staleResponseSeen' \in {staleResponseSeen, TRUE}
    /\ staleCount' \in {staleCount, staleCount + 1}
    /\ staleCount' <= StaleLimit

OpenUpdateNext == FocusedNext \/ EnvUpdate
OpenUpdateSpec == MCInit /\ [][OpenUpdateNext]_MCVars

\* Discharge: every omitted real context step satisfies the rely.
DischargeContext == [][OmittedContextActions => EnvUpdate]_MCVars

(***************************************************************************)
(* Update properties                                                       *)
(***************************************************************************)

\* REQ-EVIDENCE ElectionByVoterOnly
\* intent:   A node that is campaigning (holds a Candidate) was a voter of the effective membership it snapshotted when it started the election, i.e. learners and removed nodes never try to elect themselves.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/data/vote.md:50-51 "follower and learner in Openraft is almost the same. The only difference is a learner does not try to elect itself." -> a learner never starts an election
\* evidence: doc source/openraft/src/docs/cluster_control/cluster-control.md:14 "`Learner`: A node that cannot vote but only receives logs." -> learner role excludes campaigning
\* evidence: comment source/openraft/src/raft_state/mod.rs:341-342 "a learner node could also be possible to be a leader. Although currently it is not supported." -> learner leadership is not a supported state
\* evidence: impl source/openraft/src/core/raft_core.rs:1208-1213 "if self.engine.state.membership_state.effective().is_voter(&self.id) { ... self.engine.elect(); ... } else { // Node is switched to learner. }"
\* evidence: impl source/openraft/src/core/raft_core.rs:1454-1457 "if !self.engine.state.membership_state.effective().is_voter(&self.id) { tracing::debug!(\"this node is not a voter\"); return; }"
\* watch:    source/openraft/src/core/raft_core.rs:RaftCore::handle_api_msg; source/openraft/src/core/raft_core.rs:RaftCore::handle_tick_election; source/openraft/src/engine/engine_impl.rs:Engine::elect; source/openraft/src/engine/engine_impl.rs:Engine::new_candidate
\* verified: d7176ef (update)
\* note:     new property for the update; the old model satisfied it by the StartElection voter guard. Scenario U2.
\* review:   added for TransferLeader (new elect() caller without the voter guard).
ElectionByVoterOnly ==
    \A n \in Server :
      candidate[n] => n \in Voters(candidateConfigs[n])

\* REQ-EVIDENCE NoRaftCorePanic
\* intent:   No node's RaftCore task terminates by panicking while handling protocol messages.
\* status:   mixed
\* clause no-panic-on-vote-response: requirement — candidate.rs:92 states the contract of Candidate::grant_by ("target not in quorum set" is the expect message: callers must only pass quorum members); docs/data/vote.md:50-51 says a learner does not try to elect itself, so a learner self-grant is outside the supported protocol.
\* evidence: comment source/openraft/src/proposer/candidate.rs:92 "self.progress.update(target, true).expect(\"target not in quorum set\")" -> grant_by must only be called for a member of the candidate quorum set
\* evidence: doc source/openraft/src/docs/data/vote.md:50-51 "The only difference is a learner does not try to elect itself." -> no learner candidate, hence no learner self-grant
\* evidence: doc source/openraft/src/error.rs:122 "Fatal is unrecoverable and shuts down raft at once." (variant Panicked, error.rs:131-132) -> a panic is a fatal shutdown of the node, not a protocol outcome
\* watch:    source/openraft/src/proposer/candidate.rs:Candidate::grant_by; source/openraft/src/proposer/candidate.rs:Candidate::new; source/openraft/src/engine/engine_impl.rs:Engine::handle_vote_resp; source/openraft/src/core/raft_core.rs:RaftCore::handle_api_msg
\* verified: d7176ef (update)
\* note:     added after the U2 code observation (harness scenario specula_transfer_to_learner) exposed the panic; the model gained base!CandidateGrantPanic to express it.
\* review:   added for the update.
NoRaftCorePanic ==
    \A n \in Server : ~panicked[n]

\* Kept core safety controls (unaffected definitions; affected by new
\* elections): CommittedLogAgreement, CandidateGrantSound,
\* LeaderVoteCommitted, CurrentTermCommit -- enabled in the cfgs below.

(***************************************************************************)
(* Reachability canaries (expected to be VIOLATED; each violation is the  *)
(* non-vacuity witness for an update Scenario).                            *)
(***************************************************************************)

\* U1/U4: a TransferLeader target starts a new-term election.
CanaryTransferElect == transferLog = {}
\* U1: a TransferLeader target becomes Leader at the transfer term.
CanaryTransferLeaderWon ==
    ~ \E n \in Server : role[n] = "Leader" /\ <<n, voteTerm[n]>> \in transferLog
\* U1: the transfer leader commits an entry of its own term.
CanaryTransferCommit ==
    ~ \E n \in Server : /\ leader[n] /\ <<n, voteTerm[n]>> \in transferLog
                        /\ commitIndex[n] > 0
                        /\ EntryAt(n, commitIndex[n]).term = voteTerm[n]
\* U1: the old leader steps down after granting the transfer vote.
CanaryOldLeaderStepsDown ==
    ~ \E n, m \in Server : /\ n # m
                           /\ <<m, voteTerm[n]>> \in transferLog
                           /\ role[n] = "Follower" /\ voteNode[n] = m
                           /\ voteTerm[n] > 1
\* U2: a learner campaigns because of TransferLeader.
CanaryLearnerCandidate ==
    ~ \E n \in Server : candidate[n] /\ n \in learners[n]
\* U2: a learner candidate processes its own grant (panic path).
CanaryLearnerPanic == NoRaftCorePanic
\* U2: a learner becomes Leader (expected NOT reachable: the self-grant panics first
\* unless the candidate is replaced before its self-grant is processed).
CanaryLearnerLeader ==
    ~ \E n \in Server : role[n] = "Leader" /\ n \notin Voters(configs[n])
\* U4: crash of the transfer target after electing, before its vote is durable.
CanaryTransferCrash ==
    ~ \E n \in Server : /\ ~up[n] /\ \E t \in 0..MaxTerm : <<n, t>> \in transferLog
                        /\ durableVoteTerm[n] < voteTerm[n]

====
