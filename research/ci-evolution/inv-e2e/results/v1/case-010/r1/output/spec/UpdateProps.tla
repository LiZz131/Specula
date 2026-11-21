---------------------------- MODULE UpdateProps ----------------------------
EXTENDS base

(***************************************************************************)
(* State-only update properties of the Update lens (Update.tla extends this *)
(* module).  Kept separate so that Trace.tla evaluates the same definitions *)
(* on real traces.  Evidence: spec/invariant-evidence.json.                *)
(***************************************************************************)

\* U1 (added).  A peer that is not inside a learner sync, and whose database
\* is initialized, never carries an in-memory history that its log cannot
\* reproduce: every in-memory record is durable or has a pending (or leaked)
\* log write.  Requirement: Learner.java:553-555 ("For SNAP and TRUNC the
\* snapshot is needed to save that history"), Learner.java:612-613, the
\* update comment Learner.java:862-863 ("If we haven't finished SNAP sync,
\* force fully shutdown to avoid potential inconsistency") and the javadoc
\* of testDiffSyncAfterSnap (QuorumPeerMainTest.java:1618-1625).
\* Scenario: UPD-1 (SNAP), UPD-2 (TRUNC sibling).
\* Scope: non-leaders only.  A leader's history transiently holds a proposal
\* between Leader.propose and SyncRequestProcessor.processRequest on the
\* same thread (ProposalRequestProcessor.java:68-90; trace event 39 of
\* traces/upd-snap-exit-diff-v3.ndjson), and a peer elected leader persists
\* its database with ZooKeeperServer.loadData -> takeSnapshot
\* (ZooKeeperServer.java:480-512).
ExitedLearnerMemoryBackedByLog ==
    \A s \in Server :
        running[s] /\ role[s] /= "LEADING" /\ learnerStage[s] = "NONE" /\ ~dbCleared[s]
        => Elems(prepared[s]) \subseteq
               Elems(durable[s]) \cup Elems(syncQueued[s]) \cup LeakedElems(s)

\* U2 (added).  The recoverable history never misses a committed record
\* that precedes a later recoverable record (no committed gap).  Requirement:
\* testDiffSyncAfterSnap asserts every created node exists after reloading
\* from disk (QuorumPeerMainTest.java:1716-1730); model scope "recovered
\* histories remain mutually consistent".  Scenario: UPD-1, UPD-2.
RecoverableHistoryComplete ==
    \A s \in Server :
        \A t \in Elems(globalCommitted) :
            (\E u \in Elems(durable[s]) : u > t) => t \in Elems(durable[s])

\* U3 (added).  Replay order: every recoverable record that precedes a
\* committed record is itself committed (a never-committed record must not be
\* replayed before the committed history continues).  Requirement: model
\* scope "committed histories agree on their common prefix" applied to
\* restart replay (FileTxnSnapLog.java:317-368 replays every later record).
\* Scenario: UPD-3 (learner log drain/leak).
RecoverableCommittedPrefix ==
    \A s \in Server :
        \A i, j \in 1..Len(durable[s]) :
            i < j /\ durable[s][j] \in Elems(globalCommitted)
            => durable[s][i] \in Elems(globalCommitted)

\* U4 (added).  Restart replay is never reordered: no recoverable record
\* follows a record with a later zxid (FileTxnLog append only warns on a
\* non-increasing zxid; FileTxnSnapLog.java:317-368 logs an error and still
\* applies the record, so a stale or duplicate record after a newer one
\* re-applies old state).  Adjacent re-appends of one zxid are allowed.
\* Scenario: UPD-3.
DurableReplayOrdered == \A s \in Server : ReplayOrdered(durable[s])

\* Structural: a cleared database exists only between a SNAP-mode learner
\* exit and its reload (ZooKeeperServer.java:804-809; Learner.java:864).
ClearedOnlyAfterSnapExit ==
    \A s \in Server : dbCleared[s] => syncMode[s] = "SNAP" /\ learnerStage[s] = "NONE"

\* Revised action property (update-owned).  The update adds one more
\* source-authorized retraction: a SNAP-mode learner exit clears the
\* database (ZooKeeperServer.java:804-809), discarding an unpersisted image;
\* the retained state is the recoverable history `durable`, which is not
\* retracted.  Replaces base!MonotoneUnlessRecoveryV1 in update cfgs.
ClearStep(s) == ~dbCleared[s] /\ dbCleared'[s]
MonotoneStepUpd ==
    \A s \in Server :
        \/ RecoveryStep(s)
        \/ ClearStep(s) /\ Len(durable'[s]) >= Len(durable[s])
        \/ /\ Len(durable'[s]) >= Len(durable[s])
           /\ Len(committed'[s]) >= Len(committed[s])
           /\ Len(applied'[s]) >= Len(applied[s])
MonotoneUnlessRecoveryUpd == [][MonotoneStepUpd]_vars

\* Residual-search ordering (in-memory and commit histories only).  The
\* replay order of `durable` is judged by DurableReplayOrdered (U4), whose
\* violations are attributed in the UPD-3 hunts; residual campaigns use this
\* form to look past that class.
OrderedHistoriesMem ==
    /\ OrderedFragment(globalCommitted)
    /\ \A s \in Server :
        /\ OrderedFragment(prepared[s])
        /\ OrderedFragment(syncQueued[s])
        /\ \A q \in Elems(leakedQueued[s]) : OrderedFragment(q)
        /\ OrderedFragment(pending[s])
        /\ PrefixOf(committed[s], globalCommitted)
        /\ PrefixOf(applied[s], committed[s])

UpdateInvariants ==
    ExitedLearnerMemoryBackedByLog /\ RecoverableHistoryComplete
    /\ RecoverableCommittedPrefix /\ DurableReplayOrdered
    /\ ClearedOnlyAfterSnapExit

=============================================================================
