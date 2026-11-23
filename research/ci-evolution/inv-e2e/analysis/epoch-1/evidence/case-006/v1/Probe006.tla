------------------------------ MODULE Probe006 ------------------------------
(* Decision probes for case-006 (v1). State predicates only.                *)
EXTENDS Update

\* Stale read: r.floor = CommitWatermark at registration (base.tla:491,498).
StaleRelease(r) == r.index < r.floor
ProbeNoStale == ~\E r \in readReleases : StaleRelease(r)

\* Ack source of the OLD model (blind-incremental-v0/case-006 spec/base.tla:481-487): the
\* leader's CURRENT pending entry for the context, at the time the response is delivered.
Resp(m) == m \in messages /\ m.mtype = MsgReadIndexResp /\ m.ctx \in ReadContexts /\ alive[m.to]
OldEv(m) == IF m.from \in Server /\ pendingReads[m.from][m.ctx].active
            THEN pendingReads[m.from][m.ctx].acks \cup {m.from} ELSE {}
OldJust(m) == Cardinality(OldEv(m)) >= Quorum
\* NEW ack source (base.tla:651-669): existential choice among matching releases.
Matches(m) == {r \in readReleases : r.leader = m.from /\ r.owner = m.to /\ r.ctx = m.ctx
                                    /\ r.index = m.index /\ r.term = m.term}
\* NewJust: the delivered record CAN be justified (some candidate has a quorum);
\* NewJustAll: every candidate is justified.
NewJust(m) == \E r \in Matches(m) : Cardinality(r.acks) >= Quorum
NewJustAll(m) == Matches(m) /= {} /\ \A r \in Matches(m) : Cardinality(r.acks) >= Quorum
ProbeNewImpliesOld == ~\E m \in messages : Resp(m) /\ NewJust(m) /\ ~OldJust(m)
ProbeOldImpliesNew == ~\E m \in messages : Resp(m) /\ OldJust(m) /\ ~NewJustAll(m)
ProbeNewAlwaysHolds == ~\E m \in messages : Resp(m) /\ ~NewJustAll(m)
=============================================================================
