---- MODULE Probe_v2c002_S05 ----
\* Dismissal (spec/output/update/campaign-summary.md:63-64): "With one transaction
\* (`Txn = {t1}`) no ghost is possible in those single-txn runs."
\* Canary: a ghost under the revised formulation -- a broadcasting follower's durable log
\* holds a txn its live current leader never proposed -- in the single-txn focused cfg
\* (Update-focused-syncedlog.cfg, Txn = {t1}, from MCInit).
EXTENDS Update
Canary == ~SyncedLogMatchesLeader
NotCanary == ~Canary
====
