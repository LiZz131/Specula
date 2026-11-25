---- MODULE Debug ----
EXTENDS Update
NoCandWithPre == ~\E i \in Server : candidateActive[i] /\ preCandidateActive[i]
NoLeader == ~\E i \in Server : role[i] = "Leader"
NoCandWithPreAndVoteReq == ~\E i \in Server : candidateActive[i] /\ preCandidateActive[i] /\ (\E m \in messages : m.kind = "VoteReq" /\ m.source = i)
====
