---- MODULE Probe_v2c011_S10 ----
\* Dismissal (modeling-brief.md:370-372): "a Pre-Vote quorum also bypasses `enable_elect` and the
\* voter check ...; with followers' rounds cancelled by AppendEntries this is reachable only on
\* own-vote (candidate/leader) nodes, i.e. through MC-1/MC-2."
\* Canary (action): a Pre-Vote quorum calls elect() on a node that is a Follower or Learner (not
\* an own-vote node) and is not a voter of its effective configuration (voter check bypassed).
EXTENDS Update
Canary == \E i \in Server :
            /\ PreVoteQuorumElectStep(i)
            /\ role[i] \in {"Follower", "Learner"}
            /\ ~InConfig(i, effectiveConfig[i])
NotCanaryAct == [][~Canary]_vars
====
