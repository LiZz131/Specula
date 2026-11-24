---- MODULE CensusProbes ----
EXTENDS Update

\* US1: "release frees request ... map and queue both empty after release (PendingMatchesQueue)"
\* (output/modeling-brief.md:206) -- ghost flag set when advance releases (frees) a context.
SC_US1 == scenarioSeen.readFreed

\* US2: "released context admitted again in same term ... new instance pending with new index"
\* (output/modeling-brief.md:207)
SC_US2 == scenarioSeen.readReenqueue

\* US3: "delayed ack from earlier instance releases new instance ... ack must postdate request"
\* (output/modeling-brief.md:208) -- a release whose counted acks include a peer that did not ack
\* this instance (acks \ fresh /= {}).
SC_US3 == \E r \in readReleases : r.acks \ r.fresh /= {}

\* US4: "US3 after a newer leader committed" (output/modeling-brief.md:209)
SC_US4 == \E r \in readReleases :
            /\ r.acks \ r.fresh /= {}
            /\ \E ch \in commitHistory : ch.commitTerm > r.term

\* US5: "reset discards pending reads ... queue/map cleared" (output/modeling-brief.md:210)
SC_US5 == scenarioSeen.resetDropsRead

\* US6: "forwarded read released and consumed ... justification preserved after delete"
\* (output/modeling-brief.md:211) -- a follower consumed a MsgReadIndexResp after a release.
SC_US6 == scenarioSeen.readResponse /\ scenarioSeen.readFreed

\* positive control
SC_CTRL == scenarioSeen.leader
====
