---- MODULE Probe_v2c011_S06 ----
\* Dismissal (spec/UpdateProps.tla:69): "admin rounds (ExternalCommand::Elect { pre_vote: true })
\* are excluded: they check only is_voter and carry a TODO about leaders (raft_core.rs:1685), so an
\* operator-requested demotion is not forbidden by any cited evidence."
\* Canary (action): the excluded case -- a non-timer (operator) Pre-Vote round reaches quorum and
\* calls elect() on a node that is Leader.
EXTENDS Update
Canary == \E i \in Server :
            /\ PreVoteQuorumElectStep(i) /\ ~preCandidateByTimer[i] /\ role[i] = "Leader"
NotCanaryAct == [][~Canary]_vars
====
