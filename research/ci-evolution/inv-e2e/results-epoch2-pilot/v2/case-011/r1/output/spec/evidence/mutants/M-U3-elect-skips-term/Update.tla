------------------------------ MODULE Update ------------------------------
(***************************************************************************
 * Update-focused checking lens for the Pre-Vote revision.                 *
 *                                                                         *
 * All behavior is owned by base.tla / MC.tla. This module only selects    *
 * reference/MC Actions, defines the open-environment rely for omitted     *
 * membership/log context, and states update-specific properties.          *
 *                                                                         *
 * Source update (synthetic commit "update"):                              *
 *   engine/engine_impl.rs   pre_candidate, new_pre_candidate, pre_elect,  *
 *                           handle_pre_vote_req, handle_pre_vote_resp,    *
 *                           do_elect clears pre_candidate                 *
 *   vote_handler/mod.rs     become_following clears pre_candidate         *
 *   core/raft_core.rs       tick pre-vote branch, ExternalCommand::Elect  *
 *                           {pre_vote}, RequestPreVote handler,           *
 *                           PreVoteResponse routing and                   *
 *                           does_pre_candidate_vote_match, SendPreVote    *
 *   proposer/candidate.rs   starting_time (tick rate limiting)            *
 *   config/*, raft/*        enable_pre_vote switch, Trigger::elect(bool)  *
 *************************************************************************)
EXTENDS MC, UpdateProps

PreVoteKinds == {"PreVoteReq", "PreVoteResp"}

\* ---------------------------------------------------------------------------
\* PreVoteSetup / PreVoteVars / PreVoteMessages
\* The reference constant PreVoteNodes (config.rs:Config::enable_pre_vote,
\* runtime_config_handle.rs:pre_vote) selects which tick path TickElect takes;
\* ExternalPreElect (trigger.rs:Trigger::elect(true)) is independent of it.
\* preCandidate* / preGrants / sendPreVotePending mirror Engine.pre_candidate
\* and the queued Command::SendPreVote; preRound / preByTimer and the message
\* field `round` are ghost observers used only by the properties below.
\* ---------------------------------------------------------------------------

\* ---------------------------------------------------------------------------
\* Affected Actions: directly changed reference Actions, in MC form.
\* reference: base!TickElect, base!PreElect, base!DoElectCore (via
\*   MCTickElect/MCExternalElect/MCExternalPreElect/MCStartTransferElection),
\*   base!SendPreVoteRequests, base!HandlePreVoteRequest,
\*   base!HandlePreVoteResponse
\* code: core/raft_core.rs:1959-2036,1683-1690,2342-2344,1551-1562,1803-1820,
\*       2067-2090; engine/engine_impl.rs:262-322,414-446,516-554
\* ---------------------------------------------------------------------------
AffectedTriggers ==
    \E i \in Server : MCTickElect(i) \/ MCExternalElect(i) \/ MCExternalPreElect(i)
                        \/ MCStartTransferElection(i)

AffectedReactive ==
    /\ MCReactivePreVote
    /\ UNCHANGED faultCounters

AffectedActions == AffectedTriggers \/ AffectedReactive

\* ---------------------------------------------------------------------------
\* Interaction Actions: unchanged or minimally edited reference Actions that
\* establish, consume, cancel, or recover the Pre-Vote state.
\* reference: base!HandleVoteResponse (establish_leader keeps pre_candidate),
\*   base!HandleVoteRequest / base!HandleAppendEntries / base!RefreshServerState
\*   (become_following drops pre_candidate), base!PersistVote,
\*   base!SendVoteRequest, base!FinishVoteBroadcast, base!SendAppendEntries,
\*   base!ExpireLease (lease gate of pre-vote replies and of the tick),
\*   base!Crash / base!Restart, base!DropMessage
\* code: engine/engine_impl.rs:855-880; vote_handler/mod.rs:106-162,234-252;
\*       engine_impl.rs:107-120
\* ---------------------------------------------------------------------------
InteractionReactive ==
    /\ \/ \E i \in Server :
             Old!PersistVote(i) \/ Old!FinishVoteBroadcast(i)
             \/ Old!ExpireLease(i) \/ Old!Restart(i) \/ Old!RefreshServerState(i)
       \/ \E i \in Server, j \in Server :
             Old!SendVoteRequest(i, j) \/ Old!SendAppendEntries(i, j)
       \/ \E m \in messages :
             Old!DeliverVoteRequest(m) \/ Old!DeliverVoteResponse(m)
             \/ Old!DeliverAppendEntries(m)
    /\ UNCHANGED faultCounters

InteractionFaults ==
    \/ \E i \in Server : MCCrash(i)
    \/ \E m \in messages : MCDropMessage(m)

InteractionActions == InteractionReactive \/ InteractionFaults

\* Omitted real context: leader-side membership evolution, commit, and the
\* log/config flush callback. They do not read or write Pre-Vote state, votes,
\* roles, or messages, but change effective configuration and logs that a
\* later Pre-Vote round snapshots.
\* reference: base!AppendJointConfig, base!AppendUniformConfig,
\*   base!CommitMembership, base!FlushLog
OmittedContext ==
    \/ \E i \in Server, target \in SUBSET Server : MCAppendJointConfig(i, target)
    \/ \E i \in Server : MCAppendUniformConfig(i)
    \/ /\ \E i \in Server : Old!CommitMembership(i) \/ Old!FlushLog(i)
       /\ UNCHANGED faultCounters

\* ---------------------------------------------------------------------------
\* EnvUpdate: rely for the omitted context. One live node changes only its
\* configuration/log bookkeeping. A configuration change must be made by an
\* established self-leader, may install ANY valid one- or two-part
\* configuration (weaker than the coherent joint->uniform evolution), keeps
\* at most one uncommitted configuration, and appends one own log entry.
\* Votes, roles, candidate/leader/pre-candidate state, leases, and messages
\* are untouched. Durable log/config may catch up to the projected values.
\* ---------------------------------------------------------------------------
OtherNodesConfigLogUnchanged(i) ==
    \A j \in Server \ {i} :
        /\ committedConfig'[j] = committedConfig[j]
        /\ committedConfigIndex'[j] = committedConfigIndex[j]
        /\ effectiveConfig'[j] = effectiveConfig[j]
        /\ effectiveConfigIndex'[j] = effectiveConfigIndex[j]
        /\ durableConfig'[j] = durableConfig[j]
        /\ durableConfigIndex'[j] = durableConfigIndex[j]
        /\ lastLog'[j] = lastLog[j]
        /\ durableLastLog'[j] = durableLastLog[j]
        /\ logFlushPending'[j] = logFlushPending[j]

NonEmptySets == (SUBSET Server) \ {{}}
AllConfigs ==
    {<<a>> : a \in NonEmptySets} \cup
    {<<a, b>> : a \in NonEmptySets, b \in NonEmptySets}

EnvConfigStep(i) ==
    /\ leaderActive[i]
    /\ vote[i].committed /\ vote[i].node = i
    /\ \/ \* install a new effective configuration (one new own log entry)
          /\ committedConfigIndex[i] = effectiveConfigIndex[i]
          /\ effectiveConfigIndex[i] < MaxLogIndex
          /\ lastLog[i].index < MaxLogIndex
          /\ effectiveConfig'[i] \in AllConfigs
          /\ effectiveConfigIndex'[i] = effectiveConfigIndex[i] + 1
          /\ committedConfig'[i] = effectiveConfig[i]
          /\ committedConfigIndex'[i] = effectiveConfigIndex[i]
          /\ lastLog'[i] = Log(vote[i].term, i, lastLog[i].index + 1)
          /\ logFlushPending'[i] = TRUE
          /\ faultCounters.membership < MaxMembershipCount
          /\ faultCounters' = [faultCounters EXCEPT !.membership = @ + 1]
       \/ \* commit the outstanding configuration
          /\ committedConfigIndex[i] < effectiveConfigIndex[i]
          /\ committedConfig'[i] = effectiveConfig[i]
          /\ committedConfigIndex'[i] = effectiveConfigIndex[i]
          /\ effectiveConfig'[i] = effectiveConfig[i]
          /\ effectiveConfigIndex'[i] = effectiveConfigIndex[i]
          /\ lastLog'[i] = lastLog[i]
          /\ logFlushPending'[i] = logFlushPending[i]
          /\ UNCHANGED faultCounters
    /\ durableConfig'[i] = durableConfig[i]
    /\ durableConfigIndex'[i] = durableConfigIndex[i]
    /\ durableLastLog'[i] = durableLastLog[i]

EnvFlushStep(i) ==
    /\ logFlushPending[i]
    /\ durableLastLog'[i] = lastLog[i]
    /\ durableConfig'[i] = effectiveConfig[i]
    /\ durableConfigIndex'[i] = effectiveConfigIndex[i]
    /\ logFlushPending'[i] = FALSE
    /\ committedConfig'[i] = committedConfig[i]
    /\ committedConfigIndex'[i] = committedConfigIndex[i]
    /\ effectiveConfig'[i] = effectiveConfig[i]
    /\ effectiveConfigIndex'[i] = effectiveConfigIndex[i]
    /\ lastLog'[i] = lastLog[i]
    /\ UNCHANGED faultCounters

EnvUpdate ==
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, messages, preVars>>
    /\ \E i \in Server :
          /\ ~crashed[i]
          /\ OtherNodesConfigLogUnchanged(i)
          /\ EnvConfigStep(i) \/ EnvFlushStep(i)

\* ---------------------------------------------------------------------------
\* Specs
\* ---------------------------------------------------------------------------
\* Full: the complete MC reference (update properties checked over MCNext).
UpdateFullSpec == MCSpec

\* Concrete focused: changed mechanism plus its high-risk interactions.
UpdateFocusedNext == AffectedActions \/ InteractionActions
UpdateFocusedSpec == MCInit /\ [][UpdateFocusedNext]_mcVars

\* Open focused: concrete focus plus the rely for omitted context.
UpdateOpenNext == UpdateFocusedNext \/ EnvUpdate
UpdateOpenSpec == MCInit /\ [][UpdateOpenNext]_mcVars

\* Discharge: every omitted real context step satisfies the rely (checked
\* over the full MC reference behavior, frame included in EnvUpdate).
DischargeContext == [][OmittedContext => EnvUpdate]_mcVars

\* Completeness of the partition: every MCNext step is selected by the focus
\* or is omitted context (checked over the full MC reference behavior).
FocusPartitionComplete == [][MCNext => (UpdateFocusedNext \/ OmittedContext)]_mcVars

\* ---------------------------------------------------------------------------
\* Update-specific properties: step/state predicates and their REQ-EVIDENCE
\* blocks live in UpdateProps.tla; here they are checked over MC behaviors.
\* ---------------------------------------------------------------------------
PreVoteResponderSideEffectFree == [][PreVoteResponderSideEffectFreeStep]_mcVars
PreVoteRequesterSideEffectFree == [][PreVoteRequesterSideEffectFreeStep]_mcVars
PreVoteElectionAtPreVotedTerm == [][PreVoteElectionAtPreVotedTermStep]_mcVars
PreVoteStaleResponseIgnored == [][PreVoteStaleResponseIgnoredStep]_mcVars
TimerPreVoteElectionFromFollowerState == [][TimerPreVoteElectionFromFollowerStateStep]_mcVars

\* ---------------------------------------------------------------------------
\* Reachability canaries (expected to be VIOLATED; non-vacuity witnesses).
\* ---------------------------------------------------------------------------
\* REQ-EVIDENCE CanaryNoPreVoteElection
\* intent:   reachability canary: some Pre-Vote quorum starts an election.
\* status:   model-internal
\* watch:    none
\* verified: update
CanaryNoPreVoteElection == [][~\E i \in Server : PreVoteElection(i)]_mcVars
\* REQ-EVIDENCE CanaryNoPreVoteTally
\* intent:   reachability canary: a granted Pre-Vote response is tallied without reaching quorum.
\* status:   model-internal
\* watch:    none
\* verified: update
CanaryNoPreVoteTally ==
    [][~\E i \in Server : PreVoteRespConsumed(i) /\ preGrants'[i] /= preGrants[i]
                           /\ preCandidateActive'[i]]_mcVars
\* REQ-EVIDENCE CanaryNoPreVoteLeaseReject
\* intent:   reachability canary: a lease-holding follower answers a Pre-Vote request.
\* status:   model-internal
\* watch:    none
\* verified: update
CanaryNoPreVoteLeaseReject ==
    [][~\E i \in Server : PreVoteReqHandled(i) /\ vote[i].committed /\ leaseValid[i]]_mcVars
\* REQ-EVIDENCE CanaryNoGreaterLogFromPreVote
\* intent:   reachability canary: a rejected Pre-Vote response with a greater log sets seen_greater_log.
\* status:   model-internal
\* watch:    none
\* verified: update
CanaryNoGreaterLogFromPreVote ==
    [][~\E i \in Server : PreVoteRespConsumed(i) /\ ~seenGreaterLog[i] /\ seenGreaterLog'[i]]_mcVars
\* REQ-EVIDENCE CanaryNoPreCandidateDroppedByFollowing
\* intent:   reachability canary: an unchanged consumer (become_following) drops an active pre-candidate.
\* status:   model-internal
\* watch:    none
\* verified: update
CanaryNoPreCandidateDroppedByFollowing ==
    [][~\E i \in Server : preCandidateActive[i] /\ ~preCandidateActive'[i]
                          /\ ~ElectedNow(i) /\ ~crashed'[i] /\ ~crashed[i]]_mcVars
\* REQ-EVIDENCE CanaryNoLeaderWithTimerRound
\* intent:   reachability canary: an established Leader still holds a timer-started Pre-Vote round.
\* status:   model-internal
\* watch:    none
\* verified: update
CanaryNoLeaderWithTimerRound ==
    ~\E i \in Server : role[i] = "Leader" /\ preCandidateActive[i] /\ preByTimer[i]
\* REQ-EVIDENCE CanaryNoSameLeaderIdNewRound
\* intent:   reachability canary: a node starts a second Pre-Vote round with the same leader id while a response to the earlier round is in flight.
\* status:   model-internal
\* watch:    none
\* verified: update
CanaryNoSameLeaderIdNewRound ==
    ~\E i \in Server : \E m \in messages :
        /\ m.kind = "PreVoteResp" /\ m.dest = i
        /\ preCandidateActive[i]
        /\ SameLeaderId(m.vote, preCandidateVote[i])
        /\ m.round /= preRound[i]

\* REQ-EVIDENCE CanaryNoCertifiedLeader
\* intent:   reachability canary: some node wins an election in the 3-voter universe (guards the vacuity found in the prior suite).
\* status:   model-internal
\* watch:    none
\* verified: update
CanaryNoCertifiedLeader == ~\E i \in Server : leaderCertified[i]

=============================================================================
