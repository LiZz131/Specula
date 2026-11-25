---- MODULE PriorCanary ----
\* Evidence-only wrapper over the unchanged prior V0 MC module.
EXTENDS MC
PriorNoLeader == \A i \in Server : role[i] /= "Leader"
PriorNoGrantedRemoteVote == \A m \in messages : (m.kind = "VoteResp" /\ m.granted) => m.source = m.dest
====
