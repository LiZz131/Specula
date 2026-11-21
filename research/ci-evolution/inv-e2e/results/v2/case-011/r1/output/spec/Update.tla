------------------------------ MODULE Update ------------------------------
(***************************************************************************
 * Update-focused checking lens for the Pre-Vote revision.                 *
 *                                                                         *
 * All behavior is owned by base.tla / MC.tla. This module only selects    *
 * the changed (Affected) and interacting reference Actions, defines an    *
 * open environment for the omitted context, and states the update         *
 * properties. Analysis: modeling-brief.md Section 2 (Scenarios U1-U6).    *
 *************************************************************************)
EXTENDS MC, UpdateProps

(***************************************************************************
 * Update-visible state.                                                    *
 * reference: base!preCandidateActive ... base!preRound                     *
 * code: openraft/src/engine/engine_impl.rs:95-101,149-165                  *
 *************************************************************************)
PreVoteVisibleState == <<preVoteVars, vote, role, leaderActive, candidateActive,
                         effectiveConfig, messages>>

\* reference: base!PreVoteMessage; code: openraft/src/core/raft_msg/mod.rs:69-73,
\* openraft/src/core/notification.rs:34-44
PreVoteMessageKinds == {"PreVoteReq", "PreVoteResp"}

(***************************************************************************
 * Affected Actions (MC forms of every directly changed reference Action). *
 *************************************************************************)
\* reference: base!TickPreElect, base!ExternalPreElect, base!PreElect
\* code: openraft/src/engine/engine_impl.rs:297-322; openraft/src/core/raft_core.rs:1683-1696,2010-2035
PreElectAction == \E i \in Server : MCTickPreElect(i) \/ MCExternalPreElect(i)

\* reference: base!TickElect (now gated by TickPreVoteModes), base!ElectEffects
\* code: openraft/src/core/raft_core.rs:2010-2035; openraft/src/engine/engine_impl.rs:262-289
TickElectAction == \E i \in Server : MCTickElect(i) \/ MCExternalElect(i)

\* reference: base!HandlePreVoteRequest
\* code: openraft/src/engine/engine_impl.rs:414-447; openraft/src/core/raft_core.rs:1551-1562
HandlePreVoteRequestAction ==
    /\ \E m \in messages : Ref!DeliverPreVoteRequest(m)
    /\ UNCHANGED faultCounters

\* reference: base!HandlePreVoteResponse
\* code: openraft/src/engine/engine_impl.rs:516-554; openraft/src/core/raft_core.rs:1803-1820
HandlePreVoteResponseAction ==
    /\ \E m \in messages : Ref!DeliverPreVoteResponse(m)
    /\ UNCHANGED faultCounters

AffectedActions ==
    \/ PreElectAction
    \/ TickElectAction
    \/ HandlePreVoteRequestAction
    \/ HandlePreVoteResponseAction

(***************************************************************************
 * Interaction Actions: concrete unchanged Actions that establish, consume, *
 * cancel or recover the Pre-Vote round (PreCandidateClearPaths), plus the *
 * real-election machinery that a Pre-Vote quorum hands over to.           *
 *************************************************************************)
\* reference: base!HandleVoteRequest, base!HandleVoteResponse, base!HandleAppendEntries,
\*            base!Restart (all run PreCandidateCleared), base!PersistVote,
\*            base!SendVoteRequest, base!FinishVoteBroadcast, base!SendAppendEntries,
\*            base!ExpireLease, base!Crash, base!DropMessage
\* code: openraft/src/engine/handler/vote_handler/mod.rs:106-161,172-249;
\*       openraft/src/engine/engine_impl.rs:349-511,855-881
PreCandidateClearPaths ==
    \/ /\ \E m \in messages : Ref!DeliverVoteRequest(m) \/ Ref!DeliverVoteResponse(m)
                                \/ Ref!DeliverAppendEntries(m)
       /\ UNCHANGED faultCounters
    \/ /\ \E i \in Server : Ref!Restart(i)
       /\ UNCHANGED faultCounters

InteractionActions ==
    \/ PreCandidateClearPaths
    \/ /\ \E i \in Server : Ref!PersistVote(i) \/ Ref!FinishVoteBroadcast(i) \/ Ref!ExpireLease(i)
       /\ UNCHANGED faultCounters
    \/ /\ \E i, j \in Server : Ref!SendVoteRequest(i, j) \/ Ref!SendAppendEntries(i, j)
       /\ UNCHANGED faultCounters
    \/ \E i \in Server : MCCrash(i)
    \/ \E m \in messages : MCDropMessage(m)

(***************************************************************************
 * Omitted context in the focused models: leader-local membership/log       *
 * evolution, commit, cached-role refresh, log flush, and leadership         *
 * transfer elections. EnvUpdate is the rely they must satisfy.             *
 *************************************************************************)
OmittedContextActions ==
    \/ \E i \in Server, t \in SUBSET Server : Ref!AppendJointConfig(i, t)
    \/ \E i \in Server : Ref!AppendUniformConfig(i) \/ Ref!CommitMembership(i)
                         \/ Ref!RefreshServerState(i) \/ Ref!FlushLog(i)
                         \/ Ref!StartTransferElection(i)

NextConfigs(c) ==
    IF Len(c) = 1
    THEN {<<c[1], t>> : t \in (SUBSET Server) \ {{}, c[1]}}
    ELSE {<<c[2]>>}

\* Rely for one omitted step on node i. Weaker than the omitted Actions: it
\* does not require a single outstanding membership entry, lets the cached
\* role drop to the membership-derived role without the commit fence, and
\* lets an election-start step be any do_elect from a member.
EnvMembershipLog(i) ==
    /\ leaderActive[i] /\ vote[i].committed /\ vote[i].node = i
    /\ lastLog[i].index < MaxLogIndex
    /\ effectiveConfigIndex[i] < MaxLogIndex
    /\ \E c \in NextConfigs(effectiveConfig[i]) :
         effectiveConfig' = [effectiveConfig EXCEPT ![i] = c]
    /\ effectiveConfigIndex' = [effectiveConfigIndex EXCEPT ![i] = @ + 1]
    /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ lastLog' = [lastLog EXCEPT ![i] = Log(vote[i].term, i, lastLog[i].index + 1)]
    /\ logFlushPending' = [logFlushPending EXCEPT ![i] = TRUE]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, durableLastLog,
                    durableConfig, durableConfigIndex, messages, preVoteVars>>

EnvCommitOrFlush(i) ==
    /\ \/ /\ committedConfigIndex[i] < effectiveConfigIndex[i]
          /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
          /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
          /\ UNCHANGED <<durableLastLog, logFlushPending, durableConfig, durableConfigIndex>>
       \/ /\ logFlushPending[i]
          /\ durableLastLog' = [durableLastLog EXCEPT ![i] = lastLog[i]]
          /\ logFlushPending' = [logFlushPending EXCEPT ![i] = FALSE]
          /\ durableConfig' = [durableConfig EXCEPT ![i] = effectiveConfig[i]]
          /\ durableConfigIndex' = [durableConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
          /\ UNCHANGED <<committedConfig, committedConfigIndex>>
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, lastLog,
                    effectiveConfig, effectiveConfigIndex, messages, preVoteVars>>

EnvRoleRefresh(i) ==
    LET r == RoleFrom(i, vote[i], effectiveConfig[i]) IN
    /\ role' = [role EXCEPT ![i] = r]
    /\ leaderActive' = [leaderActive EXCEPT ![i] = IF r = "Leader" THEN @ ELSE FALSE]
    /\ candidateActive' = [candidateActive EXCEPT ![i] = IF r = "Candidate" THEN @ ELSE FALSE]
    /\ \E clear \in BOOLEAN :
         /\ (r \notin {"Leader", "Candidate"}) => clear
         /\ Ref!PreCandidateCleared(i, clear)
    /\ UNCHANGED <<crashed, seenGreaterLog, voteVars, candidateVote, candidateConfig,
                    grants, sentVoteReq, leaderVote, leaderCertified, leaderConfig,
                    leaderGrants, logVars, configVars, messages>>

EnvElect(i) ==
    /\ InConfig(i, effectiveConfig[i])
    /\ Ref!ElectEffects(i, TRUE, FALSE, messages)

EnvUpdate ==
    \E i \in Server :
        /\ ~crashed[i]
        /\ \/ EnvMembershipLog(i)
           \/ EnvCommitOrFlush(i)
           \/ EnvRoleRefresh(i)
           \/ EnvElect(i)

\* The rely may not create a Pre-Vote round, grant a pre-vote, change any vote,
\* durable vote or message, or resurrect leader/candidate state.
EnvFrame ==
    \A i \in Server :
        /\ preCandidateActive'[i] => preCandidateActive[i]
        /\ preRound'[i] = preRound[i]
        /\ preCandidateActive'[i] => /\ preCandidateVote'[i] = preCandidateVote[i]
                                     /\ preGrants'[i] = preGrants[i]
        /\ durableVote'[i] = durableVote[i]
        /\ leaderActive'[i] => leaderActive[i]

(***************************************************************************
 * Focused and open specifications.                                        *
 *************************************************************************)
UpdateFocusedNext == AffectedActions \/ InteractionActions
UpdateFocusedSpec == MCInit /\ [][UpdateFocusedNext]_mcVars

OpenUpdateNext ==
    \/ AffectedActions
    \/ InteractionActions
    \/ EnvUpdate /\ UNCHANGED faultCounters
OpenUpdateSpec == MCInit /\ [][OpenUpdateNext]_mcVars

(***************************************************************************
 * Discharge obligation: every omitted context step satisfies the rely,     *
 * including the frame on update-visible state. Checked over full MCSpec.   *
 *************************************************************************)
DischargeContext ==
    [][OmittedContextActions => (EnvUpdate /\ EnvFrame)]_mcVars

=============================================================================
