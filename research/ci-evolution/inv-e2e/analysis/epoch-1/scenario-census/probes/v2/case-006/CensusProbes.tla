---- MODULE CensusProbes ----
EXTENDS MC
\* Census precondition probes for v2/case-006 (state predicates only; no actions).
\* scenarioSeen, servedReads, commitHistory and pending-read stamps are the arm's own history/ghost state.

\* U1 "advance now deletes every released request; the pending map and the FIFO queue name the same
\* contexts." (output/modeling-brief.md:234-235) -> a release has freed pending state
SC_U1 == scenarioSeen.readFreed

\* U2 "after a context is released and freed, the same caller context can be registered again by the
\* same leader in the same term" (output/modeling-brief.md:243-245)
SC_U2a == scenarioSeen.readReuse
\* U2 "A heartbeat response produced for the *earlier* registration, still in flight, is therefore counted
\* for the new registration" (output/modeling-brief.md:248-250)
SC_U2b == scenarioSeen.staleAck
\* U2 canary list "HuntReuseServed" (output/modeling-brief.md:257-258): the same context released twice
\* by one leader in one term (the re-registered read is answered)
SC_U2c == \E a, b \in servedReads : a /= b /\ a.leader = b.leader /\ a.term = b.term /\ a.ctx = b.ctx

\* U3 "if, between the earlier acknowledgement and the re-registration, the other servers elect a newer
\* leader and commit an entry, the old leader can still release the re-registered read"
\* (output/modeling-brief.md:263-266) -> a leader holds a re-registered pending read while an entry
\* committed in a higher term exists
SC_U3 == \E i \in Server, c \in ReadContexts :
           /\ role[i] = Leader /\ pendingReads[i][c].active
           /\ \E sr \in servedReads : sr.leader = i /\ sr.term = term[i] /\ sr.ctx = c
           /\ \E ch \in commitHistory : ch.commitTerm > term[i]

\* U4 "remote requests are released into MsgReadIndexResp ... consumed by followers"
\* (output/modeling-brief.md:273-274) around freed entries
SC_U4a == scenarioSeen.readResponse /\ scenarioSeen.readFreed
\* U4 "leaders that step down or change term recreate readOnly" (output/modeling-brief.md:274-275)
\* -> a server that broadcast a read-context heartbeat in its current term is no longer leader
SC_U4b == \E i \in Server :
            /\ role[i] /= Leader
            /\ \E m \in messages : m.mtype = MsgHeartbeat /\ m.from = i
                                   /\ m.ctx \in ReadContexts /\ m.term = term[i]

\* U4 "leaders that step down or change term recreate `readOnly`" (output/modeling-brief.md:274-275), full
\* wording (step down OR change term): a server that broadcast a read-context heartbeat as leader is no
\* longer leader, or has moved to a higher term, while that heartbeat is still in flight
SC_U4b2 == \E i \in Server : \E m \in messages :
             /\ m.mtype = MsgHeartbeat /\ m.from = i /\ m.ctx \in ReadContexts
             /\ (role[i] /= Leader \/ m.term < term[i])

\* Positive control: a read was served.
SC_CTRL == servedReads /= {}
====
