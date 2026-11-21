------------------------------ MODULE Update ------------------------------
(***************************************************************************)
(* Update-focused checking view for case-010 (artifact "baseline" ->       *)
(* "update").  The reference suite (base/MC) owns every behavior; this      *)
(* module only selects the changed MC Actions, the concrete interacting     *)
(* Actions, the open environment, and the update-specific properties.      *)
(*                                                                         *)
(* Source delta (exact):                                                   *)
(*   Learner.java:850-866        zk.shutdown() -> zk.shutdown(syncMode==SNAP)*)
(*   ZooKeeperServer.java:803-810 !canShutdown && fully -> zkDb.clear()     *)
(*   QuorumPeerMainTest.java      testDiffSyncAfterSnap (+NEWLEADER hook)   *)
(*                                                                         *)
(* Effects represented in the reference (base.tla UPDATE-MAP comments):     *)
(*   - LearnerFully / dbInitialized: unfinished SNAP sync drops the reused  *)
(*     in-memory database, so the next getLastLoggedZxid reloads from disk; *)
(*   - LearnerDrains: the one-argument call bypasses the                    *)
(*     LearnerZooKeeperServer.shutdown() override, so a serving learner's   *)
(*     SyncRequestProcessor is no longer drained/stopped (leakedQueued).    *)
(***************************************************************************)
EXTENDS MC, UpdateProps

FocusLeader == CHOOSE s \in Server : TRUE
Others == Server \ {FocusLeader}

(***************************************************************************)
(* Affected Actions: MC forms of the directly changed reference Actions.    *)
(***************************************************************************)
\* reference: base!LearnerExit / base!LearnerShutdownEffects
\* code: zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:850-866
\* code: zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java:803-810
\* reference: base!ReloadDatabase (consumer of the cleared database)
\* code: zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:1257-1262
AffectedActions ==
    \/ \E f \in Others : MCLearnerExit(f)
    \/ \E s \in Others : MCReload(s)

(***************************************************************************)
(* Interaction Actions: unchanged producers/consumers of the changed state. *)
(*  producer  : ReceiveSyncMode (SNAP image / TRUNC cut), SyncApplyCommitted *)
(*  boundary  : PersistSyncSnapshot, LearnerAckNewLeader (fully -> false)   *)
(*  consumer  : JoinEstablishedLeader + ReceiveSyncMode(DIFF) on the reused *)
(*              database, FollowerPendingProposal/QueueForSync/FlushTxnLog   *)
(*  leak      : LeakedFlush of a processor zk.shutdown(boolean) left running *)
(*  context   : stable-leader election/discovery/commit pipeline, follower   *)
(*              crash/restart                                               *)
(***************************************************************************)
InteractionActions ==
    \/ \E v \in Server : MCCastVote(v, FocusLeader)
    \/ \E s \in Server : MCFinishElection(s, FocusLeader)
    \/ \E s \in Others : MCJoinLeader(s, FocusLeader)
    \/ \E s \in Server : MCEnterDiscovery(s)
    \/ MCPersistLeaderAccepted(FocusLeader)
    \/ \E f \in Others : MCPersistFollowerAccepted(f)
    \/ \E f \in Server : MCRecordEpochAck(FocusLeader, f)
    \/ MCFormEpochQuorum(FocusLeader)
    \/ \E f \in Others : MCPersistFollowerCurrent(f)
    \/ \E f \in Others : MCEnterFollowerSync(f)
    \/ \E f \in Others : \E m \in {"DIFF", "TRUNC", "SNAP"} : MCDecideSync(f, m)
    \/ \E f \in Others : \E m \in {"DIFF", "TRUNC", "SNAP"} : MCReceiveSync(f, m)
    \/ \E f \in Others : \E t \in Txn : MCSyncApply(f, t)
    \/ \E f \in Others : MCPersistSyncSnapshot(f)
    \/ \E f \in Others : MCAckNewLeader(f)
    \/ \E f \in Others : MCCompleteSync(f)
    \/ MCFormNewLeaderQuorum(FocusLeader)
    \/ MCLeaderBroadcast(FocusLeader)
    \/ \E f \in Others : MCFollowerBroadcast(f)
    \/ MCLeaderPropose(FocusLeader)
    \/ \E f \in Others : \E t \in Txn : MCFollowerPending(f, t)
    \/ \E s \in Server : \E t \in Txn : MCQueue(s, t)
    \/ \E s \in Server : \E t \in Txn : MCFlush(s, t)
    \/ \E s \in Others : \E t \in Txn : MCLeakedFlush(s, t)
    \/ \E source \in Server : \E t \in Txn : MCAck(FocusLeader, source, t)
    \/ \E t \in Txn : MCCommit(FocusLeader, t)
    \/ \E f \in Others : \E t \in Txn : MCFollowerCommit(f, t)
    \/ \E s \in Server : \E t \in Txn : MCApply(s, t)
    \/ \E f \in Others : MCCrash(f)
    \/ \E f \in Others : MCRestart(f)

UpdateFocusNext == AffectedActions \/ InteractionActions

\* FocusLeader is fixed; the two other servers are interchangeable in the focus.
UpdSymmetry == Permutations(Others)

(***************************************************************************)
(* Scenario-isolation views (restrict the enabled Action set only).         *)
(***************************************************************************)
\* U1 only: no TRUNC session, and no leaked-processor flush.
NoTruncStep == \A f \in Server : syncPlan'[f].mode /= "TRUNC"
NoLeakFlushStep == \A s \in Server : Len(leakedQueued'[s]) >= Len(leakedQueued[s])
SnapFixNext == UpdateFocusNext /\ NoTruncStep /\ NoLeakFlushStep
\* U3 only: no direct in-memory COMMIT application and no SNAP session (so the
\* old-code control cannot reach U1); the leaked-processor path remains.
NoSyncApplyStep == \A f \in Server : recoveryVisible'[f] = recoveryVisible[f]
                                      \/ learnerStage'[f] /= "MODE"
                                      \/ learnerStage[f] /= "MODE"
NoSnapStep == \A f \in Server : syncPlan'[f].mode /= "SNAP"
LeakNext == UpdateFocusNext /\ NoSyncApplyStep /\ NoSnapStep
\* U2 only (end-to-end): any session mode, no leaked-processor flush.
TruncNext == UpdateFocusNext /\ NoLeakFlushStep

(***************************************************************************)
(* Open focus: omitted periodic-snapshot context is replaced by EnvUpdate.  *)
(* The rely may change only snapshot bookkeeping (publishing at most the    *)
(* server's applied history) and the snapshot counter/coverage marks; every *)
(* update-visible variable is preserved.  Leader crash, global election     *)
(* rounds and leader restart are outside the focused view (stable-leader    *)
(* scope); they remain covered only by the full-MCNext campaigns.           *)
(***************************************************************************)
UpdateVisible ==
    <<running, role, phase, syncMode, leaderOf, syncComplete, prepared,
      syncQueued, pending, durable, recoveryVisible, committed, applied,
      globalCommitted, dbInitialized, learnerStage, sessionMode, logCursor,
      leakedQueued, syncCommitCut, syncPlan, newLeaderAcks, newLeaderReady, acks, durabilityEvidence,
      commitWitness, nextTxn, acceptedEpoch, currentEpoch, epochProposal,
      electionRound, votedFor, electionVotes, epochAcks>>

EnvUpdate ==
    /\ UNCHANGED UpdateVisible
    /\ \E s \in Server :
         /\ snapshotBusy' \in {snapshotBusy, [snapshotBusy EXCEPT ![s] = ~@]}
         /\ snapshotImage' \in {snapshotImage, [snapshotImage EXCEPT ![s] = applied[s]]}
         /\ snapshotPublished' \in {snapshotPublished,
                                    [snapshotPublished EXCEPT ![s] = snapshotImage[s]]}
    /\ counters' \in {counters, [counters EXCEPT !.snapshots = @ + 1]}
    /\ seen' \in {seen, seen \cup {"BeginSnapshot"}, seen \cup {"FinishSnapshot"}}

OpenUpdateNext == UpdateFocusNext \/ EnvUpdate

OmittedContextActions ==
    \E s \in Server : MCBeginSnapshot(s) \/ MCFinishSnapshot(s)

\* Discharge: every omitted real context step is accepted by the rely.
DischargeContext == [][OmittedContextActions => EnvUpdate]_mcvars

(***************************************************************************)
(* Update-specific properties                                               *)
(***************************************************************************)

UpdateInvariants == UpdIdleDbBackedByDisk /\ UpdDurableCoversCommitted

(***************************************************************************)
(* Reachability canaries (expected to be violated: witness of the Scenario) *)
(***************************************************************************)
\* REQ-EVIDENCE UpdSnapAbortUnreachable
\* intent:   reachability canary, expected to be violated: a learner left a SNAP session before NEWLEADER (stale QuorumPeer syncMode SNAP while LOOKING)
\* status:   model-internal
\* verified: update (case-010)
\* review:   ok
UpdSnapAbortUnreachable ==
    ~\E s \in Server : running[s] /\ role[s] = "LOOKING" /\ syncMode[s] = "SNAP"
                       /\ learnerStage[s] = "IDLE"
\* REQ-EVIDENCE UpdSnapClearUnreachable
\* intent:   reachability canary, expected to be violated in CodeVersion new: zk.shutdown(true) cleared the database of a running peer
\* status:   model-internal
\* verified: update (case-010)
\* review:   ok
UpdSnapClearUnreachable == ~\E s \in Server : running[s] /\ ~dbInitialized[s]
\* REQ-EVIDENCE UpdTruncAbortUnreachable
\* intent:   reachability canary, expected to be violated: a learner left a TRUNC session before NEWLEADER after a direct in-memory COMMIT application
\* status:   model-internal
\* verified: update (case-010)
\* review:   ok
UpdTruncAbortUnreachable ==
    ~\E s \in Server : running[s] /\ role[s] = "LOOKING" /\ syncMode[s] = "TRUNC"
                       /\ learnerStage[s] = "IDLE"
                       /\ Len(recoveryVisible[s]) > Len(durable[s])
\* REQ-EVIDENCE UpdRejoinUnreachable
\* intent:   reachability canary, expected to be violated: after a learner exit some follower completed a later NEWLEADER ACK (rejoin consumer of the reused or reloaded database)
\* status:   model-internal
\* verified: update (case-010)
\* review:   ok
UpdRejoinUnreachable ==
    ~(counters.exits > 0 /\ \E s \in Others : learnerStage[s] = "NEWLEADER"
                             /\ Len(prepared[s]) > 0 /\ "LearnerShutdown" \in seen)
\* REQ-EVIDENCE UpdLeakUnreachable
\* intent:   reachability canary, expected to be violated in CodeVersion new: a serving learner's sync processor queue survived zk.shutdown
\* status:   model-internal
\* verified: update (case-010)
\* review:   ok
UpdLeakUnreachable == ~\E s \in Server : Len(leakedQueued[s]) > 0

=============================================================================
