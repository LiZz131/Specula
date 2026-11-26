--------------------------- MODULE EvidenceTrace ---------------------------
(***************************************************************************
 * Divergence-evidence evaluation over TRACE-VALIDATED states.             *
 * Replays a fresh implementation trace with Trace.tla and, in every       *
 * reached state, evaluates the PRIOR property definitions (OldBase, the   *
 * prior base.tla with only the MODULE line renamed) next to the current    *
 * ones.  The Update properties need the MC ghost preOrigin; for a trace    *
 * the origin of the (single) round is the caller recorded by its PreElect  *
 * event (EvidenceOrigin).                                                  *
 *************************************************************************)
EXTENDS Trace

CONSTANT EvidenceOrigin

Old == INSTANCE OldBase

OriginFromTrace == [i \in Server |-> IF preCandidateActive[i] THEN EvidenceOrigin ELSE "none"]

U == INSTANCE Update WITH
        faultCounters <- [election |-> 0, preVote |-> 0, membership |-> 0, crash |-> 0, drop |-> 0],
        preOrigin <- OriginFromTrace,
        MaxElectionCount <- 9, MaxPreVoteCount <- 9, MaxMembershipCount <- 9,
        MaxCrashCount <- 9, MaxDropCount <- 9, MaxMessageCount <- 99

Report ==
    PrintT(<<"EVIDENCE", "cursor", cursor,
             "TypeOK(old,new)", Old!TypeOK, TypeOK,
             "VoteRequestAfterDurable(old,new)", Old!VoteRequestAfterDurable, VoteRequestAfterDurable,
             "GrantedResponseAfterDurable(old,new)", Old!GrantedResponseAfterDurable, GrantedResponseAfterDurable,
             "LeaderRoleHasCommittedSelfVote(old,new)", Old!LeaderRoleHasCommittedSelfVote, LeaderRoleHasCommittedSelfVote,
             "CandidateRoleHasPendingSelfVote(old,new)", Old!CandidateRoleHasPendingSelfVote, CandidateRoleHasPendingSelfVote,
             "NoForgedMessageEndpoints(old,new)", Old!NoForgedMessageEndpoints, NoForgedMessageEndpoints,
             "TickPreVoteRoundNotHeldByLeader", U!TickPreVoteRoundNotHeldByLeader,
             "PreVoteGrantsWithinFrozenVoters", U!PreVoteGrantsWithinFrozenVoters,
             "CandidateGrantsWithinFrozenVoters", U!CandidateGrantsWithinFrozenVoters,
             "PreCandidateWellFormed", PreCandidateWellFormed,
             "records(msgKinds,role1,preActive1)", {m.kind : m \in messages}, role["1"], preCandidateActive["1"]>>)

EvidenceReport == Report
UTimerPreempt == U!LeaderNotPreemptedByTimerPreVote
UProbed == U!PreVoteElectionAtProbedVote
UNoPersist == U!PreVoteStepsDoNotPersist
=============================================================================
