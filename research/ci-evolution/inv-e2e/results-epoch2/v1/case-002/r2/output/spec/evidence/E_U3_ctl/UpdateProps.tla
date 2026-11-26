---------------------------- MODULE UpdateProps ----------------------------
(* Update-specific properties for case-002 (see Update.tla header).  Defined *)
(* over base variables only, so Trace-derived states can be checked too.     *)
EXTENDS base

(* ---------------- Update properties ----------------------------------- *)
\* Learner `s` has written the NEWLEADER ACK to its current, still-leading
\* leader of the same epoch.
AckedToLiveLeader(s) ==
    /\ up[s] /\ role[s] = "following"
    /\ learnerStage[s] \in {"acked", "uptodate"}
    /\ leaderOf[s] \in Server
    /\ up[leaderOf[s]] /\ role[leaderOf[s]] = "leading"
    /\ acceptedEpoch[leaderOf[s]] = acceptedEpoch[s]

\* U1 (update effect).  The NEWLEADER ACK is written only after the leader's
\* initial history acknowledged by it has been handed to the learner's log
\* pipeline (logRequest -> SyncRequestProcessor queue).
\* Scenario US-1; code: Learner.java:748-760.  Expected: holds for the update,
\* violated by the old-behaviour control (NewLeaderLogsPending = FALSE).
AckedHistoryHandedOff ==
    \A s \in Server :
        AckedToLiveLeader(s) => IsPrefix(InitialHistory(leaderOf[s]), queued[s])

\* U2 (update intent / Zab NEWLEADER contract).  A learner whose NEWLEADER ACK
\* was counted holds the acknowledged initial history durably.
\* Requirement evidence: Learner.java:748 "make sure sync the uncommitted logs
\* before commit them (ACK NEWLEADER)"; DIFFSyncConsistencyTest.java:124-131,
\* 186-188.  Scenario US-2.
NewLeaderAckDurable ==
    \A s \in Server :
        AckedToLiveLeader(s) => IsPrefix(InitialHistory(leaderOf[s]), durable[s])

\* U3 (consumer-visible interaction).  A leader that starts serving in epoch e
\* serves every entry that an earlier-epoch leader committed/served.
\* Requirement evidence: DIFFSyncConsistencyTest.java:186-201 ("Data
\* inconsistency detected", "violation of ZAB").  Scenario US-3.
CommittedSurvivesLeaderChange ==
    \A l \in Server :
        (up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast") =>
            \A c \in everCommitted :
                c.cepoch < acceptedEpoch[l] => HasEntry(committed[l], c.entry)

=============================================================================
