---- MODULE Probe_v2c004_N02 ----
\* Dismissal (spec/bug-report.md:133): "U2 learner leadership (canary) ... not reachable within
\* budget (code: self-grant panics first)".
\* Canary: the agent's own CanaryLearnerLeader situation -- a node is Leader while it is not
\* a voter of its own effective configuration.
EXTENDS Update
Canary == \E n \in Server : role[n] = "Leader" /\ n \notin Voters(configs[n])
NotCanary == ~Canary
====
