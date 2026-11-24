---- MODULE Probe_v2c012_N01 ----
\* Dismissal (analysis-report.md:118; modeling-brief.md:208): "The covered-but-unpromoted state is
\* produced by the real code only from a hand-built fixture (code observation) and was not reached
\* by the model within budget" / "stems from an internally inconsistent unit-test fixture".
\* Canary: some node's effective membership is covered by its commit index while its committed
\* membership is older (same predicate as the agent's ReachUnpromotedCoveredMembership).
EXTENDS Update
Canary == \E i \in Server : /\ effectiveMembershipIndex[i] <= committed[i]
                            /\ committedMembershipIndex[i] < effectiveMembershipIndex[i]
NotCanary == ~Canary
====
