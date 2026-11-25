------------------------------ MODULE Update ------------------------------
(***************************************************************************
 * Update-focused checking lens for the Pre-Vote revision (artifact commit  *
 * 3ab6cdd "update" over 1adc857 "baseline").                               *
 *                                                                         *
 * All behaviour is owned by base.tla / MC.tla. This module only selects   *
 * MC actions, defines update-specific properties, reachability canaries,  *
 * the focused/open specs, and the discharge obligation.                   *
 *************************************************************************)
EXTENDS MC

(***************************************************************************
 * Affected Actions (directly changed reference behaviour)                 *
 *************************************************************************)
\* reference: base!TickElect (Pre-Vote branch)
\* code: openraft/src/core/raft_core.rs:2010-2035
TickElectAffected == \E i \in Server, pv \in BOOLEAN : MCTickElect(i, pv)

\* reference: base!ExternalPreElect, base!ExternalElect, base!StartTransferElection
\*            (all reach base!DoElect, which now clears the pre-candidate)
\* code: openraft/src/core/raft_core.rs:1683-1696; engine_impl.rs:262-264
ExternalElectAffected ==
    \E i \in Server : MCExternalPreElect(i) \/ MCExternalElect(i) \/ MCStartTransferElection(i)

\* reference: base!HandlePreVoteRequest
\* code: openraft/src/engine/engine_impl.rs:414-447; raft_core.rs:1551-1562
HandlePreVoteRequestAffected ==
    \E m \in messages : Old!DeliverPreVoteRequest(m) /\ UNCHANGED faultCounters

\* reference: base!HandlePreVoteResponse (+ base!DoElect on quorum)
\* code: openraft/src/engine/engine_impl.rs:516-554; raft_core.rs:1803-1820,2066-2090
HandlePreVoteResponseAffected ==
    \E m \in messages : Old!DeliverPreVoteResponse(m) /\ UNCHANGED faultCounters

AffectedActions ==
    \/ TickElectAffected
    \/ ExternalElectAffected
    \/ HandlePreVoteRequestAffected
    \/ HandlePreVoteResponseAffected

(***************************************************************************
 * Interaction Actions (unchanged code that produces/consumes the changed  *
 * state). Each one either clears or preserves Engine.pre_candidate        *
 * (vote_handler/mod.rs:154-160,242-244), consumes the election started by *
 * a Pre-Vote quorum, or changes the lease/log inputs of the pre-vote      *
 * guard (engine_impl.rs:429-446).                                          *
 *************************************************************************)
InteractionReactive ==
    \/ \E i \in Server :
          \/ Old!PersistVote(i) \/ Old!FinishVoteBroadcast(i) \/ Old!FlushLog(i)
          \/ Old!ExpireLease(i) \/ Old!RefreshServerState(i)
          \/ \E j \in Server : Old!SendVoteRequest(i, j) \/ Old!SendAppendEntries(i, j)
    \/ \E m \in messages :
          \/ Old!DeliverVoteRequest(m)     \* old consumer; become_following clears pre_candidate
          \/ Old!DeliverVoteResponse(m)    \* establish_leader keeps pre_candidate
          \/ Old!DeliverAppendEntries(m)   \* lease + log recency (R-1); clears pre_candidate

InteractionActions ==
    \/ InteractionReactive /\ UNCHANGED faultCounters
    \/ \E i \in Server : MCCrash(i) \/ MCRestart(i)
    \/ \E m \in messages : MCDropMessage(m)

(***************************************************************************
 * Omitted context: ordinary membership evolution. It never touches vote,  *
 * pre-candidate, candidate or message state, but it changes the effective *
 * config read by TickElect/PreElect and the leader's last log read by the *
 * pre-vote log guard.                                                     *
 *************************************************************************)
OmittedContextActions ==
    \/ \E i \in Server, target \in SUBSET Server : MCAppendJointConfig(i, target)
    \/ \E i \in Server : MCAppendUniformConfig(i)
    \/ \E i \in Server : Old!CommitMembership(i) /\ UNCHANGED faultCounters

\* EnvUpdate: a current leader replaces its effective config by a coherent
\* successor (uniform -> joint over the same old part, joint -> its new part),
\* moving committed to the previous effective config and appending one log
\* entry under its own vote; or any node commits its outstanding config.
\* Everything else, including all Pre-Vote/vote/candidate/leader/message and
\* durable state, is preserved.
CoherentSuccessor(c) ==
    IF Len(c) = 1
    THEN {<<c[1], t>> : t \in (SUBSET Server) \ {{}, c[1]}}
    ELSE {<<c[2]>>}

EnvFrame ==
    UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, durableLastLog,
                appendBehindVote, durableConfig, durableConfigIndex, messages, preVars>>

EnvUpdate ==
    \/ \E i \in Server :
          /\ ~crashed[i]
          /\ leaderActive[i] /\ vote[i].committed /\ vote[i].node = i
          /\ committedConfigIndex[i] = effectiveConfigIndex[i]
          /\ effectiveConfigIndex[i] < MaxLogIndex
          /\ lastLog[i].index < MaxLogIndex
          /\ \E nc \in CoherentSuccessor(effectiveConfig[i]) :
                effectiveConfig' = [effectiveConfig EXCEPT ![i] = nc]
          /\ effectiveConfigIndex' = [effectiveConfigIndex EXCEPT ![i] = @ + 1]
          /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
          /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
          /\ lastLog' = [lastLog EXCEPT ![i] = Log(vote[i].term, i, lastLog[i].index + 1)]
          /\ logFlushPending' = [logFlushPending EXCEPT ![i] = TRUE]
          /\ EnvFrame
          /\ faultCounters.membership < MaxMembershipCount
          /\ faultCounters' = [faultCounters EXCEPT !.membership = @ + 1]
    \/ \E i \in Server :
          /\ ~crashed[i]
          /\ committedConfigIndex[i] < effectiveConfigIndex[i]
          /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
          /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
          /\ UNCHANGED <<effectiveConfig, effectiveConfigIndex, lastLog, logFlushPending,
                          faultCounters>>
          /\ EnvFrame

FocusedNext == AffectedActions \/ InteractionActions
OpenUpdateNext == AffectedActions \/ InteractionActions \/ EnvUpdate

FocusedSpec == MCInit /\ [][FocusedNext]_mcVars
OpenSpec == MCInit /\ [][OpenUpdateNext]_mcVars

\* Discharge: every omitted real context step satisfies the rely (checked over
\* the full MCSpec reachable state space).
DischargeContext == [][OmittedContextActions => EnvUpdate]_mcVars

(***************************************************************************
 * Update properties                                                       *
 *************************************************************************)

\* U1 (structural/update). An in-flight Pre-Vote round always probes exactly
\* "my vote at term + 1": the real election it may trigger (engine_impl.rs:
\* 536-539 -> elect() at state.vote.term + 1) is the vote the quorum answered.
\* Scenario U-S1. Requirement: pre_vote.md:28-33,47-49 ("would you grant me a
\* vote at term + 1"; "If a quorum would grant, the node runs the real
\* election").
PreCandidateProbesNextTerm ==
    \A i \in Server :
        preActive[i] => /\ preVote[i].term = vote[i].term + 1
                        /\ preVote[i].node = i
                        /\ ~preVote[i].committed

\* U2 (interaction, action property). A Pre-Vote quorum never turns an
\* established Leader into a Candidate. Scenario U-S3. Requirement:
\* pre_vote.md:3-6 (Pre-Vote is a round "a follower runs before it increments
\* its term"), pre_vote.md:13-24 (the purpose is that no inflated term
\* disrupts a healthy leader), config.rs:397-405, raft_core.rs:1966-1969
\* (leaders never start an election from the tick).
PreVoteQuorumNeverDemotesLeader ==
    [][\A i \in Server :
          ( /\ role[i] = "Leader"
            /\ \E m \in messages \ messages' : m.kind = "PreVoteResp" /\ m.dest = i )
          => role'[i] = "Leader"]_mcVars

\* U3 (liveness encoded as a safety witness). With the tick in Pre-Vote mode,
\* no operator trigger, and the down nodes staying down, a live voter majority
\* must not reach a state from which no live voter can ever assemble a
\* Pre-Vote quorum. Scenario U-S2. Requirement: tests/tests/elect/
\* t12_pre_vote.rs:188-197 ("Pre-Vote makes elections *cautious*, not
\* *impossible*: this is the core liveness requirement"), pre_vote.md:47-49.
LiveSet == {i \in Server : ~crashed[i]}

\* j's answer to i's NEXT pre-vote request, with j's lease assumed expired
\* (ExpireLease is always enabled and no leader remains to renew it).
\* engine_impl.rs:429-446
WouldGrantPreVote(j, i) ==
    /\ LogLE(lastLog[j], lastLog[i])
    /\ VoteLE(vote[j], Vote(vote[i].term + 1, i, FALSE))

\* Every grant i could ever count for its leader id (term+1, i): fresh answers,
\* grants already tallied, and granted responses still in flight (rounds at the
\* same term share the leader id that raft_core.rs:2066-2090 correlates on).
AttainablePreGrants(i) ==
    {i}
    \cup {j \in LiveSet \ {i} : WouldGrantPreVote(j, i)}
    \cup (IF preActive[i] /\ preVote[i] = Vote(vote[i].term + 1, i, FALSE)
          THEN preGrants[i] ELSE {})
    \cup {m.source : m \in {mm \in messages :
                              /\ mm.kind = "PreVoteResp" /\ mm.dest = i /\ mm.granted
                              /\ mm.round.term = vote[i].term + 1 /\ mm.round.node = i}}

PreVoteLivelock ==
    /\ TickPreVoteModes = {TRUE}
    /\ \E i \in LiveSet : InConfig(i, effectiveConfig[i])
    /\ \A i \in LiveSet :
          /\ role[i] /= "Leader" /\ ~leaderActive[i]
          /\ ~votePersistPending[i] /\ ~replyPending[i] /\ ~sendVotePending[i]
    /\ \A m \in messages : m.dest \in LiveSet => m.kind \in {"PreVoteReq", "PreVoteResp"}
    /\ \A i \in LiveSet :
          InConfig(i, effectiveConfig[i]) =>
             /\ IsQuorum(effectiveConfig[i], LiveSet)
             /\ Cardinality(ConfigVoters(effectiveConfig[i])) > 1
             /\ ~IsQuorum(effectiveConfig[i], AttainablePreGrants(i))

NoPermanentPreVoteLivelock == ~PreVoteLivelock

\* Closure obligation for U3: from any reachable livelock state, every step
\* that is neither an operator trigger, a crash, nor a restart of a down node
\* keeps the livelock (so no live voter is ever elected). Tick elections are
\* bounded by MaxElectionCount, so closure is what makes the witness
\* permanent rather than budget-limited.
LivelockStep ==
    \/ \E i \in Server, pv \in BOOLEAN : MCTickElect(i, pv)
    \/ MCReactive /\ UNCHANGED faultCounters
    \/ \E m \in messages : MCDropMessage(m)

LivelockClosed ==
    [][(PreVoteLivelock /\ LivelockStep) => PreVoteLivelock']_mcVars


(***************************************************************************
 * Witness-search monitor for Scenario U-S2 (used only as a CONSTRAINT in   *
 * MC_hunt_prevote_livelock_directed_bfs.cfg). It prunes behaviours: node   *
 * "2" never starts an election and only node "1" may crash. Every         *
 * behaviour it keeps is a behaviour of MCSpec, so a violation found under  *
 * it is a genuine witness; the absence of one proves nothing.              *
 *************************************************************************)
LivelockDirector ==
    /\ ~preActive["2"] /\ ~candidateActive["2"]
    /\ ~crashed["2"] /\ ~crashed["3"]

\* Tighter phase monitor (same pruning-only contract): node "3" starts an
\* election only after node "1" has won one; node "1" crashes only after node
\* "3" has started its real election.
LivelockDirectorPhased ==
    /\ LivelockDirector
    /\ (preActive["3"] \/ candidateActive["3"] \/ (vote["3"].node = "3" /\ vote["3"].term > 0))
          => leaderCertified["1"]
    /\ crashed["1"] => (vote["3"].node = "3" /\ vote["3"].term >= 1)

(***************************************************************************
 * Reachability canaries (expected to be VIOLATED; each violation is the   *
 * witness that the corresponding update Scenario is reachable).           *
 *************************************************************************)
CanaryNoPreCandidate == \A i \in Server : ~preActive[i]
\* Not used as a canary: with three uniform voters self + one grant is already a
\* quorum, so a tallied-but-not-elected round is unreachable by construction
\* (engine_impl.rs:534-540). The tally path is witnessed by CanaryNoLeader.
CanaryNoPreVoteTally == \A i \in Server : preActive[i] => Cardinality(preGrants[i]) < 2
CanaryNoGrantedPreVoteResp ==
    \A m \in messages : m.kind = "PreVoteResp" => ~m.granted
CanaryNoRejectedPreVoteResp ==
    \A m \in messages : m.kind = "PreVoteResp" => m.granted
CanaryNoLeader == \A i \in Server : role[i] /= "Leader"
CanaryNoLeaderWithPreCandidate == \A i \in Server : ~(role[i] = "Leader" /\ preActive[i])
CanaryNoFollowerLog == \A i \in Server : role[i] = "Follower" => ~lastLog[i].present
CanaryNoPreCandidateCleared ==
    \* a follower that has adopted a committed leader vote while a pre-vote of
    \* its own previous term was in flight
    \A i \in Server : ~(~preActive[i] /\ preVote[i].node = i /\ preVote[i].term > 0
                         /\ vote[i].committed /\ vote[i].node /= i)

=============================================================================
