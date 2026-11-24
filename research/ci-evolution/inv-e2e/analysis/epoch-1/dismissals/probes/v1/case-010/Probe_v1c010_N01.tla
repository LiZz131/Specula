---- MODULE Probe_v1c010_N01 ----
\* Dismissal (spec/bug-report.md:110): "Independent observation (not pursued, pre-existing,
\* outside the update): the TRUNC-to-maxCommittedLog path truncates a record that the
\* follower already ACKed ... temporarily reducing the number of durable copies of a
\* committed txn".
\* Canary: a globally committed transaction is durable on at most a minority of servers.
EXTENDS Update, FiniteSets
Canary == \E t \in Elems(globalCommitted) :
            2 * Cardinality({s \in Server : t \in Elems(durable[s])}) <= Cardinality(Server)
NotCanary == ~Canary
====
