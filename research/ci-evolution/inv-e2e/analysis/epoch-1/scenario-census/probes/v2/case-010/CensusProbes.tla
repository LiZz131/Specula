---- MODULE CensusProbes ----
EXTENDS Update
\* Census probes for v2/case-010 (state predicates only; no actions).

\* PC (positive control): a learner exit happened (MC counter).
SC_PC == counters.exits > 0

\* U1a. "Scenario U1: unfinished SNAP sync, then DIFF rejoin ... SNAP replaces only the in-memory DB ...
\* Abort in between -> (old) DB reused, (new) DB cleared and reloaded." (output/modeling-brief.md:200-202)
\* Encoded: a learner left a SNAP session before NEWLEADER (stale syncMode SNAP, back to LOOKING, stage IDLE).
SC_U1a == \E s \in Server : running[s] /\ role[s] = "LOOKING" /\ syncMode[s] = "SNAP"
                           /\ learnerStage[s] = "IDLE"

\* U1b. "unfinished SNAP sync, then DIFF rejoin" / "JoinEstablishedLeader, DIFF rejoin"
\* (output/modeling-brief.md:200,203). Encoded (weaker: no per-server history of the SNAP abort is
\* kept in state): after a learner exit, some follower is in a DIFF session (mode packet processed).
SC_U1b == counters.exits > 0 /\ \E s \in Server : sessionMode[s] = "DIFF"
                                 /\ learnerStage[s] \in {"MODE", "NEWLEADER"}

\* U2. "An abort before NEWLEADER leaves syncMode == TRUNC, so fullyShutDown is false and the in-memory DB
\* (ahead of the truncated log) is reused." after "COMMITs received before NEWLEADER are applied with
\* zk.processTxn without logging" (output/modeling-brief.md:207-208)
SC_U2 == \E s \in Server : running[s] /\ role[s] = "LOOKING" /\ syncMode[s] = "TRUNC"
                          /\ learnerStage[s] = "IDLE"
                          /\ Len(recoveryVisible[s]) > Len(durable[s])

\* U3a. "Scenario U3: serving learner shutdown no longer drains/stops its sync processor"
\* (output/modeling-brief.md:213). Encoded: a learner's sync-processor queue survived shutdown.
SC_U3a == \E s \in Server : Len(leakedQueued[s]) > 0

\* U3b. "The leaked processor may append its queued proposals after the learner has re-synchronized
\* (after a TRUNC cut, ...)" (output/modeling-brief.md:215)
\* Encoded: leaked queue still non-empty while the learner is in (or past) a TRUNC re-sync session.
SC_U3b == \E s \in Server : Len(leakedQueued[s]) > 0 /\ sessionMode[s] = "TRUNC"
                           /\ learnerStage[s] \in {"MODE", "SNAPPED", "NEWLEADER"}

\* U3c. "... or after the new session's processor appended later records" (output/modeling-brief.md:215)
\* Encoded: leaked queue head still pending while the learner's log already holds a later record.
SC_U3c == \E s \in Server : Len(leakedQueued[s]) > 0
                           /\ \E i \in 1..Len(durable[s]) : durable[s][i] > Head(leakedQueued[s])

\* P1. UpdIdleDbBackedByDisk intent: "a running peer that holds an initialized in-memory database between
\* following sessions (about to report getLastLoggedZxid to an election or a leader)" (spec/UpdateProps.tla:10)
\* Encoded: the property antecedent, non-trivially (after an exit, LOOKING, non-empty in-memory tree).
SC_P1 == counters.exits > 0 /\ \E s \in Server : running[s] /\ dbInitialized[s] /\ learnerStage[s] = "IDLE"
                                 /\ role[s] = "LOOKING" /\ Len(recoveryVisible[s]) > 0

\* P2. UpdDurableCoversCommitted intent: "a server's recoverable log never holds a transaction while missing
\* an earlier globally committed transaction" (spec/UpdateProps.tla:29). Encoded precondition: some server's
\* log holds a transaction later than a globally committed transaction.
SC_P2 == \E s \in Server : \E i \in 1..Len(durable[s]) :
            \E c \in Elems(globalCommitted) : c < durable[s][i]

\* P3. MonotoneUnlessRecovery (modified): "TRUNC truncation now happens at the mode packet (Learner.java:587-599)"
\* (invariant-evidence.json entries[MonotoneUnlessRecovery].affected_because). Encoded: a learner has
\* processed a TRUNC mode packet (stage MODE of a TRUNC session).
SC_P3 == \E s \in Server : sessionMode[s] = "TRUNC" /\ learnerStage[s] = "MODE"
====
