---- MODULE Probe_v1c004_S05 ----
\* Dismissal (analysis-report.md:193-196): "the Core branch has no log check. Voters still
\* reject a stale candidate by `LogId`, so safety is unaffected; effect is a possible extra
\* election (liveness)."
\* Canary: a live leader whose vote is at least as new as another node's lacks (or
\* disagrees on) an entry that the other node has already committed, i.e. a stale
\* candidate won.
EXTENDS Update
Canary == \E l, x \in Server :
            /\ l # x /\ up[l] /\ leader[l]
            /\ voteTerm[l] >= voteTerm[x]
            /\ \E i \in 1..commitIndex[x] :
                 \/ i > LastIndex(l)
                 \/ EntryAt(l, i).term # EntryAt(x, i).term
                 \/ EntryAt(l, i).node # EntryAt(x, i).node
NotCanary == ~Canary
====
