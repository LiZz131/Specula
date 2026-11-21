------------------------------ MODULE Update ------------------------------
EXTENDS MC, UpdateProps

(***************************************************************************)
(* Update-focused checking lens over the complete reference/MC suite.      *)
(* It owns no behavior: every action below is an MC wrapper of a reference *)
(* action in base.tla.                                                      *)
(*                                                                         *)
(* Source update (artifact commits baseline -> update):                    *)
(*   Learner.java:860-865   zk.shutdown(syncMode == SNAP)                   *)
(*   ZooKeeperServer.java:803-810  clear zkDb if not started and fully     *)
(*   QuorumPeerMainTest.java:1618-1743  testDiffSyncAfterSnap               *)
(***************************************************************************)

(***************************************************************************)
(* Affected actions: reference behavior that the update changed.           *)
(*   reference: base!LearnerExit / base!LearnerShutdownCore                 *)
(*   code: Learner.java:850-866; ZooKeeperServer.java:803-858               *)
(*   reference: base!ReloadDatabase (consumer of the new clear)             *)
(*   code: QuorumPeer.java:1257-1262; ZKDatabase.java:284-298               *)
(***************************************************************************)
AffectedActions ==
    \/ \E f \in Server : MCLearnerExit(f)
    \/ \E f \in Server : MCLearnerExitLeaderGone(f)
    \/ \E s \in Server : MCReloadDatabase(s)

(***************************************************************************)
(* Interaction actions: producers of the shutdown pre-state (sync start,   *)
(* SNAP load, TRUNC, in-sync apply, NEWLEADER snapshot), consumers of the  *)
(* post-state (re-election join, next sync decision, log pipeline, leaked  *)
(* processor flush), and crash/restart recovery.                           *)
(***************************************************************************)
InteractionActions ==
    \/ \E s, c \in Server : MCFinishElection(s, c)
    \/ \E s \in Server : MCEnterDiscovery(s)
    \/ \E f \in Server : MCPersistFollowerAccepted(f)
    \/ \E f \in Server : MCEnterFollowerSync(f)
    \/ \E f \in Server : \E m \in {"DIFF", "TRUNC", "SNAP"} : MCChooseSync(f, m)
    \/ \E f \in Server : MCLoadSyncSnapshot(f)
    \/ \E f \in Server : MCTruncateLog(f)
    \/ \E f \in Server : \E t \in Txn : MCApplySyncCommit(f, t)
    \/ \E f \in Server : MCBeginSyncSnapshot(f)
    \/ \E f \in Server : MCFinishSyncSnapshot(f)
    \/ \E f \in Server : MCPersistFollowerCurrent(f)
    \/ \E f \in Server : MCLearnerNewLeader(f)
    \/ \E f \in Server : MCCompleteSync(f)
    \/ \E f \in Server : MCFollowerBroadcast(f)
    \/ \E l \in Server : MCLeaderPropose(l)
    \/ \E f \in Server : \E t \in Txn : MCFollowerLog(f, t)
    \/ \E s \in Server : \E t \in Txn : MCFlush(s, t)
    \/ \E s \in Server : \E i \in 1..Len(leakedQueued[s]) : \E t \in Txn : MCFlushLeaked(s, i, t)
    \/ \E l, source \in Server : \E t \in Txn : MCAck(l, source, t)
    \/ \E l \in Server : \E t \in Txn : MCCommit(l, t)
    \/ \E f \in Server : \E t \in Txn : MCFollowerCommit(f, t)
    \/ \E s \in Server : \E t \in Txn : MCApply(s, t)
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)
    \* NEWLEADER quorum commits the new leader's history (base!NewLeaderCommit).
    \/ \E l \in Server : MCFormNewLeaderQuorum(l)

ConcreteUpdateNext == AffectedActions \/ InteractionActions

(***************************************************************************)
(* Omitted context: election-round, leader-discovery and NEWLEADER-quorum  *)
(* bookkeeping, leader BROADCAST entry, and periodic snapshots.            *)
(***************************************************************************)
OmittedContextActions ==
    \/ \E c \in Server : MCBeginElection(c)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E l \in Server : MCPersistLeaderAccepted(l)
    \/ \E l, f \in Server : MCRecordEpochAck(l, f)
    \/ \E l \in Server : MCFormEpochQuorum(l)
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ \E s \in Server : MCBeginSnapshot(s)
    \/ \E s \in Server : MCFinishSnapshot(s)

\* Update-visible state: everything the update properties or the affected
\* actions' enablement/effects read (base!LearnerShutdownCore, ReloadDatabase,
\* ChooseSyncMode, the log pipeline) other than election bookkeeping.
UpdateVisible ==
    <<running, syncMode, learnerStage, dbCleared, syncComplete,
      prepared, syncQueued, leakedQueued, pending, durable, recoveryVisible,
      committed, applied, globalCommitted, durabilityEvidence>>

\* Rely: the omitted context never changes update-visible state.  It may
\* change roles/phases/epochs/votes/quorum flags and snapshot bookkeeping, as
\* the concrete omitted actions do.
EnvUpdate == OmittedContextActions /\ UNCHANGED UpdateVisible

OpenUpdateNext == AffectedActions \/ InteractionActions \/ EnvUpdate

\* Discharge obligation (checked over full MCNext): every omitted real
\* context step satisfies the rely, including its frame on update state.
DischargeStep == OmittedContextActions => UNCHANGED UpdateVisible
DischargeContext == [][DischargeStep]_mcvars

(***************************************************************************)
(* Update-specific properties are defined in UpdateProps.tla (a state-only *)
(* part of this lens, so Trace.tla can check them on real traces).          *)
(***************************************************************************)

(***************************************************************************)
(* Reachability canaries (each expected to be VIOLATED = witness found).   *)
(***************************************************************************)
SnapExitUnpersistedUnreachable == "LearnerExitSnapUnpersisted" \notin seen
ReloadAfterSnapExitUnreachable == "ReloadAfterSnapExit" \notin seen
DiffAfterSnapReloadUnreachable ==
    ~("ReloadAfterSnapExit" \in seen /\ \E s \in Server : syncMode[s] = "DIFF" /\ learnerStage[s] /= "NONE")
TruncExitUnpersistedUnreachable == "LearnerExitTruncUnpersisted" \notin seen
ServingExitUnreachable == "LearnerExitServing" \notin seen
LeakedFlushAfterResyncUnreachable == "LeakedFlushAfterResync" \notin seen
\* A committed record is recoverable on a peer that exited after a SNAP load.
SnapExitThenCommittedRecoverableUnreachable ==
    ~("ReloadAfterSnapExit" \in seen
      /\ \E s \in Server : \E t \in Elems(globalCommitted) :
            t \in Elems(durable[s]) /\ syncComplete[s] /\ syncMode[s] = "NONE"
            /\ Len(durable[s]) >= 2)

(***************************************************************************)
(* Scenario-focused next-state relations (restrictions of MCNext).          *)
(***************************************************************************)
\* Shared context of the focused scenarios (everything in the concrete focus
\* except sync-mode choice, crashes, counted exits, and leaked flushes).
FocusCore ==
    \/ \E s, c \in Server : MCFinishElection(s, c)
    \/ \E s \in Server : MCEnterDiscovery(s)
    \/ \E f \in Server : MCPersistFollowerAccepted(f)
    \/ \E f \in Server : MCEnterFollowerSync(f)
    \/ \E f \in Server : MCLoadSyncSnapshot(f)
    \/ \E f \in Server : MCTruncateLog(f)
    \/ \E f \in Server : \E t \in Txn : MCApplySyncCommit(f, t)
    \/ \E f \in Server : MCBeginSyncSnapshot(f)
    \/ \E f \in Server : MCFinishSyncSnapshot(f)
    \/ \E f \in Server : MCPersistFollowerCurrent(f)
    \/ \E f \in Server : MCLearnerNewLeader(f)
    \/ \E f \in Server : MCCompleteSync(f)
    \/ \E f \in Server : MCFollowerBroadcast(f)
    \/ \E l \in Server : MCLeaderPropose(l)
    \/ \E f \in Server : \E t \in Txn : MCFollowerLog(f, t)
    \/ \E s \in Server : \E t \in Txn : MCFlush(s, t)
    \/ \E l, source \in Server : \E t \in Txn : MCAck(l, source, t)
    \/ \E l \in Server : \E t \in Txn : MCCommit(l, t)
    \/ \E f \in Server : \E t \in Txn : MCFollowerCommit(f, t)
    \/ \E s \in Server : \E t \in Txn : MCApply(s, t)
    \/ \E s \in Server : MCRestart(s)
    \/ \E s \in Server : MCReloadDatabase(s)
SyncWindow(f) == learnerStage[f] \in {"MODE", "DATA", "SNAPPED"}

\* UPD-1 (SNAP fix): a follower crashes and misses commits, restarts, gets a
\* SNAP (or DIFF) from the established leader, fails inside the sync window,
\* reloads/re-joins.  Leader does not crash, no TRUNC, so no serving exits.
SnapScenarioNext ==
    \/ FocusCore
    \/ \E f \in Server : \E m \in {"DIFF", "SNAP"} : MCChooseSync(f, m)
    \/ \E s \in Server : role[s] = "FOLLOWING" /\ MCCrash(s)
    \/ \E f \in Server : SyncWindow(f) /\ MCLearnerExit(f)

\* UPD-2 (TRUNC sibling): any learner exit, TRUNC allowed; leaked flushes are
\* withheld (a slow leaked thread) so the TRUNC path is isolated from UPD-3.
TruncScenarioNext ==
    \/ FocusCore
    \/ \E f \in Server : \E m \in {"DIFF", "TRUNC", "SNAP"} : MCChooseSync(f, m)
    \/ \E s \in Server : role[s] = "FOLLOWING" /\ MCCrash(s)
    \/ \E f \in Server : MCLearnerExit(f)

\* UPD-2 without any leaked processor: exits only inside the sync window
\* (before NEWLEADER no request processors exist), follower crash/restart
\* produces a follower log ahead of the leader's committed log.
TruncNoLeakNext ==
    \/ FocusCore
    \/ \E f \in Server : \E m \in {"DIFF", "TRUNC", "SNAP"} : MCChooseSync(f, m)
    \/ \E s \in Server : role[s] = "FOLLOWING" /\ MCCrash(s)
    \/ \E f \in Server : SyncWindow(f) /\ MCLearnerExit(f)

\* UPD-3 (log drain): counted exits only while serving; leaked flushes run.
LeakScenarioNext ==
    \/ FocusCore
    \/ \E f \in Server : \E m \in {"DIFF", "TRUNC", "SNAP"} : MCChooseSync(f, m)
    \/ \E s \in Server : \E i \in 1..Len(leakedQueued[s]) : \E t \in Txn : MCFlushLeaked(s, i, t)
    \/ \E f \in Server : ZkServing(f) /\ MCLearnerExit(f)

=============================================================================
