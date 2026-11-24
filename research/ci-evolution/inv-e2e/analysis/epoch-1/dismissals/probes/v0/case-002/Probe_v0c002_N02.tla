---- MODULE Probe_v0c002_N02 ----
\* Dismissal (analysis-report.md:141-144): follower applies before its own fsync;
\* "This is not a violation of the modeled property: the COMMIT packet is evidence of
\* leader-side quorum durability; the receiving follower's own fsync need not precede local apply."
\* Canary: a following server has applied history that is not durable at itself
\* AND is not durable at a majority of servers (the claimed quorum evidence absent).
EXTENDS Update, FiniteSets
Canary == \E s \in Server :
            /\ up[s] /\ role[s] = "following"
            /\ ~IsPrefix(applied[s], durable[s])
            /\ 2 * Cardinality({x \in Server : IsPrefix(applied[s], durable[x])}) <= Cardinality(Server)
NotCanary == ~Canary
====
