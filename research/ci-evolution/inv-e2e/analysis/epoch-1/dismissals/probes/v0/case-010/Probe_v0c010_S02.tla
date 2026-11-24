---- MODULE Probe_v0c010_S02 ----
\* Dismissal (modeling-brief.md:227): "same-epoch TRUNC inside queueCommittedProposals
\* (needs equal-epoch divergence that one-leader-per-epoch excludes)".
\* Canary: two servers' durable logs diverge (a has id x that b lacks, while b holds a
\* later id y > x) although no server has accepted an epoch above 1, i.e. every
\* transaction was proposed in the same (first) epoch.
EXTENDS Update
Canary == /\ \A s \in Server : acceptedEpoch[s] <= 1
          /\ \E a, b \in Server :
               \E x \in Elems(durable[a]) \ Elems(durable[b]) :
                  \E y \in Elems(durable[b]) : y > x
NotCanary == ~Canary
====
