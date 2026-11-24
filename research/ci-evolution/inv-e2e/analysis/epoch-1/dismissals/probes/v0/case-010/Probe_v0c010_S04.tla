---- MODULE Probe_v0c010_S04 ----
\* Dismissal (modeling-brief.md:233): "CR-U1 syncMode is never reset by Learner.shutdown;
\* a stale SNAP makes a later exit that fails before the first sync packet fully clear
\* (and reload) a database that is already disk-consistent. | Performance only; no
\* safety consequence found."
\* Canary (action): a learner exits before its first sync packet (syncStage IDLE) with a
\* stale syncMode = SNAP, and the in-memory database it clears is NOT the disk history.
EXTENDS Update
Canary == \E f \in Server :
            /\ syncStage[f] = "IDLE" /\ syncMode[f] = "SNAP"
            /\ syncStage'[f] = "EXITED"
            /\ memDb[f] /= durable[f]
NotCanaryAct == [][~Canary]_vars
====
