---- MODULE Probe_v1c010_S05 ----
\* Dismissal (spec/UpdateProps.tla:19-21): "Scope: non-leaders only. A leader's history
\* transiently holds a proposal between Leader.propose and SyncRequestProcessor.processRequest"
\* Canary: a running leader (not cleared) holds a record in its in-memory history that is
\* backed by neither its log, its sync queue nor a leaked queue, while a NEWER record is
\* already durable in its log -- i.e. not the transient newest-proposal case.
EXTENDS Update
Canary == \E s \in Server :
            /\ running[s] /\ role[s] = "LEADING" /\ ~dbCleared[s]
            /\ \E t \in Elems(prepared[s]) \ (Elems(durable[s]) \cup Elems(syncQueued[s]) \cup LeakedElems(s)) :
                  \E u \in Elems(durable[s]) : u > t
NotCanary == ~Canary
====
