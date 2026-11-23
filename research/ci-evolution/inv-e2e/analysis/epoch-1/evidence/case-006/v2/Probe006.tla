------------------------------ MODULE Probe006 ------------------------------
(* Decision probes for case-006 (v2). State predicates only.                *)
EXTENDS Update

\* Stale read: sr.gcommit = MaxCommitted at registration (base.tla:478,488).
StaleRelease(r) == r.index < r.gcommit
ProbeNoStale == ~\E r \in servedReads : StaleRelease(r)

\* Ack source of the OLD model (blind-incremental-v0/case-006 spec/base.tla:481-487): the
\* leader's CURRENT pending entry for the context, at the time the response is delivered.
Resp(m) == m \in messages /\ m.mtype = MsgReadIndexResp /\ m.ctx \in ReadContexts /\ alive[m.to]
OldEv(m) == IF m.from \in Server /\ pendingReads[m.from][m.ctx].active
            THEN pendingReads[m.from][m.ctx].acks \cup {m.from} ELSE {}
OldJust(m) == Cardinality(OldEv(m)) >= Quorum
\* NEW ack source (base.tla:643-648): a matching served-read record.
Matches(m) == {sr \in servedReads : sr.leader = m.from /\ sr.owner = m.to /\ sr.term = m.term
                                    /\ sr.ctx = m.ctx /\ sr.index = m.index}
NewEv(m) == IF Matches(m) = {} THEN {} ELSE (CHOOSE sr \in Matches(m) : TRUE).acks
NewJust(m) == Cardinality(NewEv(m)) >= Quorum
ProbeNewImpliesOld == ~\E m \in messages : Resp(m) /\ NewJust(m) /\ ~OldJust(m)
ProbeOldImpliesNew == ~\E m \in messages : Resp(m) /\ OldJust(m) /\ ~NewJust(m)
ProbeNewAlwaysHolds == ~\E m \in messages : Resp(m) /\ ~NewJust(m)
=============================================================================
