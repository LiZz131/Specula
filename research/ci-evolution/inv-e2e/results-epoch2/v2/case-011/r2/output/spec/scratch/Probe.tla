---- MODULE Probe ----
EXTENDS Update
P1 == ~\E i \in Server : preCandidateActive[i] /\ role[i] = "Leader"
P2 == ~\E i \in Server : preOrigin[i] = "tick" /\ candidateActive[i] /\ \E m \in messages : m.kind = "VoteResp" /\ m.dest = i /\ m.source /= i
P3 == ~\E i \in Server : preOrigin[i] = "tick" /\ candidateActive[i] /\ grants[i] = {i}
P4 == ~\E i \in Server : role[i] = "Leader"
P5 == ~\E i \in Server : Cardinality(grants[i]) >= 2
P6 == ~\E i \in Server : candidateActive[i] /\ grants[i] = {i} /\ \E m \in messages : m.kind = "VoteResp" /\ m.dest = i /\ m.source /= i /\ m.granted
====
