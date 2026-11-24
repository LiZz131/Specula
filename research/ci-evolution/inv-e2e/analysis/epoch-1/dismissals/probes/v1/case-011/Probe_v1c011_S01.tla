---- MODULE Probe_v1c011_S01 ----
\* Dismissal (modeling-brief.md:300-302): "CR-review-1 (dismissed): same-term pre-vote rounds
\* share a leader id, so a delayed earlier-round grant is counted; judged equivalent to a
\* delayed in-round grant (analysis-report §U.5). No finding."
\* Canary: a granted PreVoteResp that matches i's live pre-candidate vote is in flight to i
\* from a node j to which the CURRENT round has not sent a request (j \notin preSentReq[i],
\* reset at round start, base.tla:345), i.e. a grant from an earlier round would be counted.
EXTENDS Update
Canary == \E m \in messages : \E i \in Server :
            /\ m.kind = "PreVoteResp" /\ m.granted /\ m.dest = i
            /\ preCandidateActive[i]
            /\ m.vote.term = preCandidateVote[i].term
            /\ m.vote.node = preCandidateVote[i].node
            /\ m.source \notin preSentReq[i]
NotCanary == ~Canary
====
