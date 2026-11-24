---- MODULE Probe_v1c010_N01r ----
\* Refinement of Probe_v1c010_N01 after its first witness went through Crash/Restart instead of
\* the TRUNC path named in the dismissal (spec/bug-report.md:110).  Same canary, restricted to
\* crash-free histories (counters.crashes = 0) with every server running.
EXTENDS Update, FiniteSets
Canary == /\ counters.crashes = 0
          /\ \A s \in Server : running[s]
          /\ \E t \in Elems(globalCommitted) :
               2 * Cardinality({s \in Server : t \in Elems(durable[s])}) <= Cardinality(Server)
NotCanary == ~Canary
====
