---------------------------- MODULE EvidenceTrace ----------------------------
(***************************************************************************
 * Evaluates old (prior-suite) and current property definitions on states   *
 * and transitions reached by replaying a validated fresh trace. The prior  *
 * module is a verbatim copy of /work/previous/.specula-output/spec/base.tla *
 * renamed OldBase (MODULE line only). Values are printed with PrintT.      *
 *************************************************************************)
EXTENDS Trace, UpdateProps

Old == INSTANCE OldBase

CONSTANT EvidenceEvent   \* 1-based trace event whose transition / post-state is evaluated

PreVoteMsgs == {m \in messages : m.kind \in {"PreVoteReq", "PreVoteResp"}}

\* Post-state of event EvidenceEvent.
StateRecord ==
    (cursor = EvidenceEvent + 1) =>
        PrintT(<<"STATE", EvidenceEvent, TraceLog[EvidenceEvent].name,
                 [ records_prevote_msgs |-> Cardinality(PreVoteMsgs),
                   records_pre_candidate |-> {i \in Server : preCandidateActive[i]},
                   records_roles |-> role,
                   TypeOK_old |-> Old!TypeOK, TypeOK_new |-> TypeOK,
                   VoteRequestAfterDurable_old |-> Old!VoteRequestAfterDurable,
                   VoteRequestAfterDurable_new |-> VoteRequestAfterDurable,
                   GrantedResponseAfterDurable_old |-> Old!GrantedResponseAfterDurable,
                   GrantedResponseAfterDurable_new |-> GrantedResponseAfterDurable,
                   LeaderRoleHasCommittedSelfVote_old |-> Old!LeaderRoleHasCommittedSelfVote,
                   LeaderRoleHasCommittedSelfVote_new |-> LeaderRoleHasCommittedSelfVote,
                   CandidateRoleHasPendingSelfVote_old |-> Old!CandidateRoleHasPendingSelfVote,
                   CandidateRoleHasPendingSelfVote_new |-> CandidateRoleHasPendingSelfVote,
                   CertifiedLeaderHasFrozenQuorum_old |-> Old!CertifiedLeaderHasFrozenQuorum,
                   CertifiedLeaderHasFrozenQuorum_new |-> CertifiedLeaderHasFrozenQuorum,
                   DurableVoteNotAhead_old |-> Old!DurableVoteNotAhead,
                   DurableVoteNotAhead_new |-> DurableVoteNotAhead,
                   NoForgedMessageEndpoints_old |-> Old!NoForgedMessageEndpoints,
                   NoForgedMessageEndpoints_new |-> NoForgedMessageEndpoints,
                   PreCandidateProbeIsNextTerm |-> PreCandidateProbeIsNextTerm ]>>)

\* Transition that consumes event EvidenceEvent.
StepRecord ==
    (cursor = EvidenceEvent /\ cursor' = EvidenceEvent + 1) =>
        PrintT(<<"STEP", EvidenceEvent, TraceLog[EvidenceEvent].name,
                 [ quorum_elect_step |-> {i \in Server : PreVoteQuorumElectStep(i)},
                   round_step |-> {i \in Server : PreVoteRoundStep(i)},
                   TimerPreVoteElectsOnlyNonLeaderStep |-> TimerPreVoteElectsOnlyNonLeaderStep,
                   StalePreVoteResponseIgnoredStep |-> StalePreVoteResponseIgnoredStep,
                   PreVoteResponseNeverPanicsStep |-> PreVoteResponseNeverPanicsStep,
                   PreVoteProbeMatchesElectionStep |-> PreVoteProbeMatchesElectionStep,
                   PreVoteRoundPersistsNothingStep |-> PreVoteRoundPersistsNothingStep ]>>)

EvidenceStateInv == StateRecord
EvidenceStepProp == [][StepRecord]_traceVars
=============================================================================
