----------------------------- MODULE Update -----------------------------
(***************************************************************************
 * Update-focused checking lens for the Pre-Vote revision.                 *
 *                                                                         *
 * The reference behavior lives only in base.tla / MC.tla. This module     *
 * selects the MC forms of the changed Actions and their high-risk         *
 * interactions, defines an explicit environment rely for the omitted      *
 * membership/log context, and states update-specific properties.          *
 *                                                                         *
 * Source update: commit "update" (Pre-Vote), see analysis-report.md §U.   *
 ***************************************************************************)
EXTENDS MC

(***************************************************************************
 * Pre-candidate state and message vocabulary (reference: base.tla         *
 * VARIABLES preCandidate*, PreVoteReqMsg, PreVoteRespMsg).                *
 ***************************************************************************)
PreCandidateVars == preCandidateVars
PreVoteMessages == {m \in messages : m.kind \in {"PreVoteReq", "PreVoteResp"}}

(***************************************************************************
 * Affected Actions: every reference Action whose guard or effect changed. *
 ***************************************************************************)

\* reference: base!TickPreElect, base!PreElect
\* code: openraft/src/core/raft_core.rs:handle_tick_election;
\*       openraft/src/engine/engine_impl.rs:pre_elect,new_pre_candidate
TickPreElectFocus == \E i \in Server : MCTickPreElect(i)

\* reference: base!ExternalPreElect (trigger().elect(true))
\* code: openraft/src/core/raft_core.rs:ExternalCommand::Elect { pre_vote }
AdminPreElect == \E i \in Server : MCExternalPreElect(i)

PreElectFocus == TickPreElectFocus \/ AdminPreElect

\* reference: base!TickElect (now gated by PreVoteSetting and voter count),
\*            base!StartElection/ElectEffect (clears the pre-candidate)
\* code: raft_core.rs:handle_tick_election; engine_impl.rs:do_elect
ElectClearsPreCandidate ==
    \E i \in Server : MCTickElect(i) \/ MCExternalElect(i) \/ MCStartTransferElection(i)

\* reference: base!HandlePreVoteRequest
\* code: engine_impl.rs:handle_pre_vote_req; raft_core.rs:handle_pre_vote_request
HandlePreVoteRequestFocus ==
    /\ \E m \in messages : Old!DeliverPreVoteRequest(m)
    /\ UNCHANGED faultCounters

\* reference: base!HandlePreVoteResponse
\* code: raft_core.rs:Notification::PreVoteResponse,does_pre_candidate_vote_match;
\*       engine_impl.rs:handle_pre_vote_resp
HandlePreVoteResponseFocus ==
    /\ \E m \in messages : Old!DeliverPreVoteResponse(m)
    /\ UNCHANGED faultCounters

\* reference: base!HandleVoteRequest, base!HandleAppendEntries,
\*            base!RefreshServerState (all now clear the pre-candidate through
\*            become_following)
\* code: vote_handler/mod.rs:become_following
PreCandidateClearedByFollowing ==
    /\ \/ \E m \in messages : Old!DeliverVoteRequest(m) \/ Old!DeliverAppendEntries(m)
       \/ \E i \in Server : Old!RefreshServerState(i)
    /\ UNCHANGED faultCounters

\* reference: base!HandleVoteResponse (establish_leader keeps pre_candidate;
\*            adopting a higher vote clears it)
\* code: engine_impl.rs:handle_vote_resp,establish_leader
EstablishLeaderInteraction ==
    /\ \E m \in messages : Old!DeliverVoteResponse(m)
    /\ UNCHANGED faultCounters

\* reference: base!Restart (Engine::new resets pre_candidate)
\* code: engine_impl.rs:Engine::new
RestartClearsPreCandidate ==
    /\ \E i \in Server : Old!Restart(i)
    /\ UNCHANGED faultCounters

AffectedActions ==
    \/ PreElectFocus
    \/ ElectClearsPreCandidate
    \/ HandlePreVoteRequestFocus
    \/ HandlePreVoteResponseFocus
    \/ PreCandidateClearedByFollowing
    \/ EstablishLeaderInteraction
    \/ RestartClearsPreCandidate

(***************************************************************************
 * Interaction Actions: unchanged Actions that establish a changed         *
 * Action's precondition or observe its result.                            *
 *  - PersistVote / SendVoteRequest / FinishVoteBroadcast: the real         *
 *    election that a Candidate keeps running during its Pre-Vote round,   *
 *    and the election started by a Pre-Vote quorum.                        *
 *  - ExpireLease / SendAppendEntries: produce and remove the leader lease  *
 *    that a Pre-Vote request honors; AppendEntries also cancels the round.*
 *  - Crash / DropMessage: lose a pre-candidate or a Pre-Vote message.      *
 ***************************************************************************)
InteractionActions ==
    \/ /\ \/ \E i \in Server : Old!PersistVote(i) \/ Old!FinishVoteBroadcast(i)
                                \/ Old!ExpireLease(i)
          \/ \E i \in Server, j \in Server : Old!SendVoteRequest(i, j)
                                             \/ Old!SendAppendEntries(i, j)
       /\ UNCHANGED faultCounters
    \/ \E i \in Server : MCCrash(i)
    \/ \E m \in messages : MCDropMessage(m)

(***************************************************************************
 * Omitted context: AppendJointConfig, AppendUniformConfig,                *
 * CommitMembership, FlushLog. They change only one node's membership/log  *
 * staging and never touch vote, proposer (candidate/leader/pre-candidate),*
 * role, lease, or messages. EnvUpdate is the rely for that context. It    *
 * is deliberately weaker than the reference: it lets any node (not only a *
 * leader) step through the documented coherent evolution                  *
 * uniform -> joint -> uniform (membership/membership.rs:280-339), which    *
 * also covers a follower whose effective config changes while it holds a  *
 * Pre-Vote round (replication of membership is abstracted in base).       *
 ***************************************************************************)
NonEmpty == (SUBSET Server) \ {{}}

NextConfigs(c) ==
    IF Len(c) = 1
    THEN {<<c[1], t>> : t \in NonEmpty \ {c[1]}}
    ELSE {<<c[2]>>}

\* Rely relation over one step (no counter); used both by the open spec and
\* by the discharge obligation. Written constructively so TLC can generate
\* successors; every disjunct changes only node i's membership/log staging
\* (frame: all other variables and all other nodes unchanged).
EnvUpdateStep ==
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, messages,
                   preCandidateVars>>
    /\ \E i \in Server :
        /\ ~crashed[i]
        /\ \/ \* append the next membership entry (projected, not yet durable)
              /\ committedConfigIndex[i] = effectiveConfigIndex[i]
              /\ effectiveConfigIndex[i] < MaxLogIndex
              /\ lastLog[i].index < MaxLogIndex
              \* Entries are appended under the current vote's leader id, which
              \* is never behind the existing last log id (log ids grow). Repair
              \* after update-open-residual: without this conjunct the rely let a
              \* restarted node append under an older term (Case B, rely too weak).
              /\ LogLT(lastLog[i], Log(vote[i].term, vote[i].node, lastLog[i].index + 1))
              /\ \E c \in NextConfigs(effectiveConfig[i]) :
                    effectiveConfig' = [effectiveConfig EXCEPT ![i] = c]
              /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
              /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
              /\ effectiveConfigIndex' = [effectiveConfigIndex EXCEPT ![i] = @ + 1]
              /\ lastLog' = [lastLog EXCEPT ![i] = Log(vote[i].term, vote[i].node, lastLog[i].index + 1)]
              /\ logFlushPending' = [logFlushPending EXCEPT ![i] = TRUE]
              /\ UNCHANGED <<durableConfig, durableConfigIndex, durableLastLog>>
           \/ \* commit the outstanding membership entry
              /\ committedConfigIndex[i] < effectiveConfigIndex[i]
              /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
              /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
              /\ UNCHANGED <<effectiveConfig, effectiveConfigIndex, durableConfig,
                             durableConfigIndex, lastLog, durableLastLog, logFlushPending>>
           \/ \* projected log/config become durable
              /\ logFlushPending[i]
              /\ logFlushPending' = [logFlushPending EXCEPT ![i] = FALSE]
              /\ durableLastLog' = [durableLastLog EXCEPT ![i] = lastLog[i]]
              /\ durableConfig' = [durableConfig EXCEPT ![i] = effectiveConfig[i]]
              /\ durableConfigIndex' = [durableConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
              /\ UNCHANGED <<committedConfig, committedConfigIndex, effectiveConfig,
                             effectiveConfigIndex, lastLog>>

MaxEnvCount == MaxMembershipCount + 2

EnvUpdate ==
    /\ faultCounters.env < MaxEnvCount
    /\ EnvUpdateStep
    /\ faultCounters' = [faultCounters EXCEPT !.env = @ + 1]

(***************************************************************************
 * Discharge: every omitted real context Action satisfies the rely and    *
 * its frame. Checked as an action property over full MCSpec.              *
 ***************************************************************************)
OmittedContextActions ==
    \/ \E i \in Server, target \in SUBSET Server : MCAppendJointConfig(i, target)
    \/ \E i \in Server : MCAppendUniformConfig(i)
    \/ \E i \in Server : Old!CommitMembership(i) \/ Old!FlushLog(i)

DischargeEnv == [][OmittedContextActions => EnvUpdateStep]_mcVars

(***************************************************************************
 * Focused and open specifications.                                         *
 ***************************************************************************)
FocusedNext == AffectedActions \/ InteractionActions
FocusedSpec == MCInit /\ [][FocusedNext]_mcVars

OpenUpdateNext == AffectedActions \/ InteractionActions \/ EnvUpdate
OpenUpdateSpec == MCInit /\ [][OpenUpdateNext]_mcVars

(***************************************************************************
 * Update properties.                                                      *
 ***************************************************************************)

\* Scenario U3 (pre-vote round x election in flight x leader establishment).
\* A Leader object never runs behind the local vote. RaftCore relies on this
\* whenever it obtains the leader handler:
\*   engine_impl.rs:try_leader_handler debug_assert!(
\*       leader.committed_vote >= state.vote)
\* and the timer path never starts an election on a Leader
\*   (raft_core.rs:handle_tick_election "skip election, already a leader").
\* Scoped to autonomous behavior: admin triggers (trigger().elect) may elect
\* on a Leader by design ("TODO: reject if it is already a leader?"), so cfgs
\* checking this property set AllowAdminElect = FALSE.
LeaderVoteCoversLocalVote ==
    \A i \in Server : leaderActive[i] => VoteLE(vote[i], leaderVote[i])

\* Scenario U1/U2. A live Pre-Vote round always probes exactly the term the
\* subsequent elect() will use (vote.term + 1, own node, uncommitted):
\* pre_elect derives it from vote.term; do_elect re-derives it from vote.term.
\* engine_impl.rs:pre_elect, do_elect; docs/protocol/pre_vote.md
PreCandidateTracksNextTerm ==
    \A i \in Server :
        preCandidateActive[i] => preCandidateVote[i] = Vote(vote[i].term + 1, i, FALSE)

\* Scenario U1. Starting or answering a Pre-Vote never changes vote, durable
\* vote, lease, or role (docs/protocol/pre_vote.md "persists nothing and
\* changes nothing"; engine_impl.rs:pre_elect, handle_pre_vote_req).
\* Observed on the reference transitions themselves.
PreVoteStepIsSideEffectFree ==
    [][ \A i \in Server :
          (\E r \in messages' \ messages :
               r.kind \in {"PreVoteReq", "PreVoteResp"} /\ r.source = i)
          => /\ vote'[i] = vote[i]
             /\ durableVote'[i] = durableVote[i]
             /\ votePersistPending'[i] = votePersistPending[i]
             /\ leaseValid'[i] = leaseValid[i]
             /\ role'[i] = role[i]
             /\ candidateActive'[i] = candidateActive[i]
             /\ leaderActive'[i] = leaderActive[i] ]_vars

UpdateTypeOK == MCTypeOK

(***************************************************************************
 * Reachability canaries (expected to be VIOLATED: each violation is a      *
 * witness that the named update Scenario is reachable in the checked cfg). *
 ***************************************************************************)
CanaryPreVoteRoundStarted == ~(\E i \in Server : preCandidateActive[i])
CanaryPreVoteGranted ==
    ~(\E m \in messages : m.kind = "PreVoteResp" /\ m.granted)
CanaryPreVoteLeaseRejected ==
    ~(\E m \in messages : m.kind = "PreVoteResp" /\ ~m.granted)
CanaryElectedViaPreVote ==
    ~(\E i \in Server : candidateActive[i] /\ faultCounters.election = 0
                         /\ faultCounters.preElect > 0)
CanaryCandidateWithPreVoteRound ==
    ~(\E i \in Server : candidateActive[i] /\ preCandidateActive[i])
CanaryLeaderWithPreVoteRound ==
    ~(\E i \in Server : leaderActive[i] /\ preCandidateActive[i])

=============================================================================
