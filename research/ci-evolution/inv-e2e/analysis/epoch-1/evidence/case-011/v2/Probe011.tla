---- MODULE Probe011 ----
\* Decision probes for the case-011 evidence card. Adds no actions; only state predicates.
EXTENDS MC

\* B trigger: a granted Pre-Vote response that matches the current round's probe, from a node
\* outside the round's frozen quorum set, can be delivered. The implementation then calls
\* Candidate::grant_by(source), whose expect("target not in quorum set") panics (candidate.rs:106-107).
BTrigger(i, m) ==
    /\ m.kind = "PreVoteResp" /\ m.dest = i /\ m.granted
    /\ preCandidateActive[i]
    /\ SameLeaderId(m.vote, preCandidateVote[i])
    /\ m.source \notin ConfigVoters(preCandidateConfig[i])
    /\ ENABLED HandlePreVoteResponse(i, m, TRUE)
ProbeNoB == ~\E i \in Server : \E m \in messages : BTrigger(i, m)

\* C trigger: a node that is no longer a voter of its effective membership can deliver a
\* Pre-Vote response that makes it start an election (term goes up), i.e. handle_pre_vote_resp
\* -> elect() without an is_voter check (engine_impl.rs:535-539).
CTrigger(i, m) ==
    /\ m.kind = "PreVoteResp" /\ m.dest = i
    /\ ~InConfig(i, effectiveConfig[i])
    /\ ENABLED (HandlePreVoteResponse(i, m, TRUE) /\ vote'[i].term > vote[i].term)
ProbeNoC == ~\E i \in Server : \E m \in messages : CTrigger(i, m)
====
