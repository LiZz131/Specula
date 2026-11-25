---------------------------- MODULE EvidenceOld ----------------------------
(***************************************************************************
 * Divergence evidence lens: evaluates the PRIOR (V0) property definitions *
 * (OldBase = verbatim copy of /work/previous/.specular-output/spec/base.tla*
 * with only the MODULE line renamed) next to the current ones, on states  *
 * of validated fresh traces. Same-named constants/variables substitute.   *
 *************************************************************************)
EXTENDS Trace

OldI == INSTANCE OldBase

OldTypeOK == OldI!TypeOK
OldGrantedResponseAfterDurable == OldI!GrantedResponseAfterDurable
OldVoteRequestAfterDurable == OldI!VoteRequestAfterDurable
OldNoForgedMessageEndpoints == OldI!NoForgedMessageEndpoints
OldLeaderRoleHasCommittedSelfVote == OldI!LeaderRoleHasCommittedSelfVote
OldCandidateRoleHasPendingSelfVote == OldI!CandidateRoleHasPendingSelfVote
OldCertifiedLeaderHasFrozenQuorum == OldI!CertifiedLeaderHasFrozenQuorum
OldDurableVoteNotAhead == OldI!DurableVoteNotAhead

\* Rejected alternative decisions (extend the durability properties to the
\* new Pre-Vote kinds); used to show the keep decision is not vacuous.
AltGrantedResponseAllKinds ==
    \A m \in messages : m.kind \in {"VoteResp", "PreVoteResp"} /\ m.granted
        => VoteLE(m.vote, durableVote[m.source])
AltVoteRequestAllKinds ==
    \A m \in messages : m.kind \in {"VoteReq", "PreVoteReq"}
        => VoteLE(m.vote, durableVote[m.source])
\* Control for TypeOK weakening: an unknown message kind is still rejected.
ControlUnknownKindRejected ==
    TypeOK => \A m \in messages : m.kind /= "Bogus"
=============================================================================
