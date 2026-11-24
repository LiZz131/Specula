---- MODULE Probe_v0c006_N03 ----
\* Dismissal (bug-report.md:116-117; analysis-report.md:286-287): "With globally unique
\* contexts the path is unreachable."
\* Canary: a release counted an acknowledgement generated before the released
\* incarnation was accepted (acks /= freshAcks, the MC-1 mechanism) although the
\* context was enqueued only once, by that leader, in the whole history
\* (readInc of every other leader is 0 and of the releasing leader is 1).
EXTENDS Update
Canary == \E r \in readReleases :
            /\ r.acks /= r.freshAcks
            /\ readInc[r.leader][r.ctx] = 1
            /\ \A j \in Server \ {r.leader} : readInc[j][r.ctx] = 0
NotCanary == ~Canary
====
