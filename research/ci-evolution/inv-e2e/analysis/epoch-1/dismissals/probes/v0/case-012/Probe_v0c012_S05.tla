---- MODULE Probe_v0c012_S05 ----
\* Dismissal (analysis-report.md:87): "C7 RaftState::update_committed ... committed-membership
\* promotion only when committed increases ... promotion checked unconditionally |
\* changed guard (equal outcomes in reachable MC states, distinguishable on fixtures)".
\* Canary: a non-leader, non-crashed server whose commit already covers its effective
\* membership while the committed membership has not been promoted to it.  In this state
\* a follower commit that does not raise `committed` promotes under the old rule and
\* does not under the new one, i.e. the outcomes differ.
EXTENDS Update
Canary == \E i \in Server :
            /\ i \notin crashed /\ role[i] # "leader"
            /\ committed[i] >= effectiveMembershipIndex[i]
            /\ committedMembershipIndex[i] # effectiveMembershipIndex[i]
NotCanary == ~Canary
====
