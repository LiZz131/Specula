------------------------------ MODULE Probe006 ------------------------------
(* Decision probes for case-006 (v0). State predicates only.                *)
EXTENDS Update

\* Stale read: a leader released a read whose index is below the largest index
\* committed anywhere when the request was registered (r.bound = MaxCommittedIndex
\* at registration, base.tla:474).
StaleRelease(r) == r.index < r.bound
ProbeNoStale == ~\E r \in readReleases : StaleRelease(r)
\* r1 -> r2 question: a stale release although a quorum of its acks was generated
\* after the request was (re-)registered (i.e. the release satisfies r2).
ProbeNoStaleFresh == ~\E r \in readReleases :
                        StaleRelease(r) /\ Cardinality(r.freshAcks) >= Quorum

\* Ack source of the OLD model (blind-incremental-v0/case-006 spec/base.tla:481-487): the
\* leader's CURRENT pending entry for the context, at the time the response is delivered.
Resp(m) == m \in messages /\ m.mtype = MsgReadIndexResp /\ m.ctx \in ReadContexts /\ alive[m.to]
OldEv(m) == IF m.from \in Server /\ pendingReads[m.from][m.ctx].active
            THEN pendingReads[m.from][m.ctx].acks \cup {m.from} ELSE {}
OldJust(m) == Cardinality(OldEv(m)) >= Quorum
\* NEW ack source (base.tla:618-624): a matching release record.
Matches(m) == {r \in readReleases : r.leader = m.from /\ r.owner = m.to /\ r.ctx = m.ctx
                                    /\ r.index = m.index /\ r.term = m.term}
NewEv(m) == IF Matches(m) = {} THEN {} ELSE (CHOOSE r \in Matches(m) : TRUE).acks
NewJust(m) == Cardinality(NewEv(m)) >= Quorum
ProbeNewImpliesOld == ~\E m \in messages : Resp(m) /\ NewJust(m) /\ ~OldJust(m)
ProbeOldImpliesNew == ~\E m \in messages : Resp(m) /\ OldJust(m) /\ ~NewJust(m)
ProbeNewAlwaysHolds == ~\E m \in messages : Resp(m) /\ ~NewJust(m)
=============================================================================
