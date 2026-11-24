---- MODULE CensusProbes ----
EXTENDS Update

\* U1a. "Scenario UPD-1: SNAP sync interrupted before NEWLEADER ... The update makes
\* `Learner.shutdown` clear the database when `syncMode==SNAP`" (output/modeling-brief.md:189-191)
\* Encoded: a SNAP-mode learner exited before NEWLEADER and its database was cleared.
SC_U1a == \E s \in Server : dbCleared[s] /\ syncMode[s] = "SNAP"

\* U1b. "... -> LearnerExit (affected) -> ReloadDatabase -> FinishElection -> ChooseSyncMode(DIFF)"
\* (output/modeling-brief.md:195). Encoded: after the SNAP exit and reload (syncMode still SNAP,
\* stage NONE, db reloaded), the follower is back in SYNCHRONIZATION and DIFF is allowed.
SC_U1b == \E s \in Server :
    /\ syncMode[s] = "SNAP" /\ learnerStage[s] = "NONE" /\ ~dbCleared[s]
    /\ running[s] /\ role[s] = "FOLLOWING" /\ phase[s] = "SYNCHRONIZATION"
    /\ leaderOf[s] \in Server /\ running[leaderOf[s]] /\ role[leaderOf[s]] = "LEADING"
    /\ SyncModeAllowed(s, leaderOf[s], "DIFF")

\* U2a. "Scenario UPD-2: TRUNC sync with in-sync COMMIT interrupted before NEWLEADER ...
\* an exit in this window keeps an unpersisted image" (output/modeling-brief.md:199-201)
\* Encoded: TRUNC mode, sync data stage, in-memory image not backed by log, exit possible.
SC_U2a == \E s \in Server :
    /\ syncMode[s] = "TRUNC" /\ learnerStage[s] = "DATA" /\ Unbacked(s)
    /\ running[s] /\ role[s] = "FOLLOWING"
    /\ (counters.exits < MaxExits \/ (leaderOf[s] \in Server /\ ~running[leaderOf[s]]))

\* U2b. "ChooseSyncMode(TRUNC) -> TruncateLog -> ApplySyncCommit -> LearnerExit -> FinishElection
\* -> ChooseSyncMode(DIFF)" (output/modeling-brief.md:203). Encoded: re-joining follower still
\* carries the unpersisted TRUNC image and DIFF is allowed.
SC_U2b == \E s \in Server :
    /\ syncMode[s] = "TRUNC" /\ learnerStage[s] = "NONE" /\ Unbacked(s)
    /\ running[s] /\ role[s] = "FOLLOWING" /\ phase[s] = "SYNCHRONIZATION"
    /\ leaderOf[s] \in Server /\ running[leaderOf[s]] /\ role[leaderOf[s]] = "LEADING"
    /\ SyncModeAllowed(s, leaderOf[s], "DIFF")

\* U3a. "Scenario UPD-3: serving learner exit no longer drains its log processor ... queued
\* writes are appended later by a leaked thread" (output/modeling-brief.md:207-209)
SC_U3a == \E s \in Server : leakedQueued[s] /= <<>>

\* U3b. "possibly after the next election/sync" (output/modeling-brief.md:209)
\* Encoded: a leaked write is still pending while the peer is again in a learner sync / leading.
SC_U3b == \E s \in Server :
    leakedQueued[s] /= <<>> /\ running[s] /\ (learnerStage[s] /= "NONE" \/ role[s] = "LEADING")

\* U3c. "and interleaved with the next lifecycle's writes" (output/modeling-brief.md:209)
SC_U3c == \E s \in Server : leakedQueued[s] /= <<>> /\ syncQueued[s] /= <<>> /\ running[s]

\* P-MON. "The update adds one more source-authorized retraction: a SNAP-mode learner exit clears
\* the database ..., discarding an unpersisted image" (output/spec/UpdateProps.tla:66-69)
\* Encoded: SNAP sync data stage whose in-memory commit history is not all durable.
SC_PMON == \E s \in Server :
    /\ syncMode[s] = "SNAP" /\ learnerStage[s] = "DATA"
    /\ ~(Elems(committed[s]) \subseteq Elems(durable[s]))

\* P-U4. "Adjacent re-appends of one zxid are allowed." (output/spec/UpdateProps.tla:57)
SC_PU4dup == \E s \in Server : \E i \in 1..(Len(durable[s]) - 1) : durable[s][i] = durable[s][i+1]

\* Positive control: at least one counted learner exit happened.
SC_CTRL == counters.exits >= 1

====
