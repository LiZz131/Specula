---- MODULE DebugU4 ----
EXTENDS Update
\* Reachability canary for the panic pre-state: an in-flight granted Pre-Vote response
\* correlated with an active round whose frozen config excludes the responder.
CanaryNoNonMemberCorrelatedGrant ==
    ~(\E m \in messages :
        /\ m.kind = "PreVoteResp" /\ m.granted
        /\ preCandidateActive[m.dest]
        /\ SameLeaderId(m.vote, preCandidateVote[m.dest])
        /\ m.source \notin ConfigVoters(preCandidateConfig[m.dest]))
CanaryNoMembershipWithPreCandidate ==
    ~(\E i \in Server : preCandidateActive[i] /\ effectiveConfigIndex[i] > 0)
CanaryNoCrash == \A i \in Server : ~crashed[i]
====
