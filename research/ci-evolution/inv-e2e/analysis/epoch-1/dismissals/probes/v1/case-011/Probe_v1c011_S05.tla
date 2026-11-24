---- MODULE Probe_v1c011_S05 ----
\* Dismissal (spec/Update.tla:210-211): "Rounds started by an administrator on a node that
\* was already Leader are excluded (pre-existing TODO at raft_core.rs:1685)."
\* Canary (action): the excluded case -- a pre-vote round that started while the node was
\* Leader reaches quorum and changes the Leader's vote (PreVoteElectStep on a Leader).
EXTENDS Update
Canary == \E i \in Server :
            /\ role[i] = "Leader"
            /\ preStartRole[i] = "Leader"
            /\ PreVoteElectStep(i)
NotCanaryAct == [][~Canary]_mcVars
====
