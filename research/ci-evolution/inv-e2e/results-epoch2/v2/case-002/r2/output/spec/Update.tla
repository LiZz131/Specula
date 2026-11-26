------------------------------ MODULE Update ------------------------------
(***************************************************************************)
(* Update-focused checking lens for source update 2efbdfc ("update").      *)
(* The reference behavior is owned by base.tla/MC.tla; this module only    *)
(* selects Actions, adds an observer for an update property, defines the   *)
(* open environment for omitted context Actions and the discharge check.   *)
(*                                                                         *)
(* Source delta (zookeeper-server/src/main/java/org/apache/zookeeper/...): *)
(*  server/quorum/Learner.java:744-761   NEWLEADER now sets sync mode NONE, *)
(*      calls zk.startupWithoutServing(), hands every buffered             *)
(*      packetsNotCommitted proposal to FollowerZooKeeperServer.logRequest *)
(*      and only then writes the NEWLEADER ACK.                            *)
(*  server/quorum/Learner.java:764-767   after UPTODATE only               *)
(*      zk.startServing() remains (was setSoTimeout/setSyncMode/startup).  *)
(*  server/ZooKeeperServer.java:669-704  startup split into                *)
(*      startupWithoutServing (INITIAL) and startServing (RUNNING).        *)
(***************************************************************************)
EXTENDS MC

(* ------------------------------------------------------------------ *)
(* Observer used only by update properties: every entry that has ever   *)
(* been part of some server's committed history.  It never constrains   *)
(* reference behavior (UpdateMonitor is a deterministic function of the *)
(* step).                                                               *)
(* ------------------------------------------------------------------ *)
VARIABLE everCommitted
uVars == <<allVars, mcVars, everCommitted>>

CommittedEntries(c) == UNION {{c[s][k] : k \in 1..Len(c[s])} : s \in Server}
UInit == MCInit /\ everCommitted = {}
UpdateMonitor == everCommitted' = everCommitted \cup CommittedEntries(committed')

(* ------------------------------------------------------------------ *)
(* Affected Actions: the reference Actions whose bodies changed.        *)
(* ------------------------------------------------------------------ *)
\* reference: base!SyncWithLeaderNewLeader
\* code: server/quorum/Learner.java:726-761; server/ZooKeeperServer.java:673-675
\* reference: base!SyncWithLeaderUpToDate
\* code: server/quorum/Learner.java:764-785; server/ZooKeeperServer.java:677-680
\* reference: base!CompleteSync (repaired V0 abstraction: the sync payload is
\*   buffered, not made durable, before NEWLEADER; Learner.java:546-711)
AffectedActions ==
    \/ \E s \in Server : MCCompleteSync(s)
    \/ \E s \in Server : MCSyncWithLeaderNewLeader(s)
    \/ \E s \in Server : MCSyncWithLeaderUpToDate(s)

(* ------------------------------------------------------------------ *)
(* Interaction Actions kept concrete.                                   *)
(*  - LeaderBroadcast: consumes the NEWLEADER ACK quorum and commits     *)
(*    the leader's initial history (Leader.java:663-712).                *)
(*  - AppendOne/FsyncOne: the SyncRequestProcessor that makes the logged *)
(*    sync proposals durable after the ACK (SyncRequestProcessor.java).  *)
(*  - Crash/Restart: cross the new ACK-before-fsync window.              *)
(*  - election/discovery/sync-selection Actions establish the affected   *)
(*    Actions' preconditions and the re-election that consumes durable   *)
(*    histories.                                                         *)
(*  - Propose/ReceiveProposal/DeliverAck/Commit/ReceiveCommit/ApplyOne:  *)
(*    produce the uncommitted leader entry and consume committed history.*)
(* ------------------------------------------------------------------ *)
InteractionActions ==
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ \E s \in Server : MCAppendOne(s)
    \/ \E s \in Server : MCFsyncOne(s)
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)
    \/ \E s \in Server : MCBeginElection(s)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s \in Server : MCWinElection(s)
    \/ \E s, l \in Server : MCFollowLeader(s, l)
    \/ \E s \in Server : MCAcceptEpoch(s)
    \/ \E l \in Server : MCFinishDiscovery(l)
    \/ \E s, l \in Server : MCEnterSyncPhase(s, l)
    \/ \E s, l \in Server, mode \in SyncModes \ {"NONE"} : MCSelectSync(s, l, mode)
    \/ \E l \in Server, t \in Txn : MCPropose(l, t)
    \/ \E m \in messages : MCReceiveProposal(m)
    \/ \E m \in messages : MCDeliverAck(m)
    \/ \E l \in Server, t \in Txn : MCCommit(l, t)
    \/ \E m \in messages : MCReceiveCommit(m)
    \/ \E s \in Server : MCApplyOne(s)

(* Omitted real context Actions of MCNext. *)
OmittedContextActions ==
    \/ \E s \in Server : MCTakeSnapshot(s)
    \/ \E m \in messages : MCDropMessage(m)

(* ------------------------------------------------------------------ *)
(* EnvUpdate: rely for the omitted context.  It may (bounded by the     *)
(* same MC counters) replace one up server's snapshot by any prefix of  *)
(* its applied history, or lose one in-flight message.  It must not     *)
(* touch update-visible state: durable/queued pipelines, committed or   *)
(* applied histories, epochs, roles, sync buffers, or NEWLEADER acks.   *)
(* ------------------------------------------------------------------ *)
EnvSnapshot ==
    /\ counters.snapshot < MaxSnapshot
    /\ \E s \in Server :
         /\ up[s]
         /\ \E k \in 0..Len(applied[s]) :
              snapshot' = [snapshot EXCEPT ![s] = SubSeq(applied[s], 1, k)]
    /\ counters' = [counters EXCEPT !.snapshot = @ + 1]
    /\ seen' = seen \cup {"snapshot"}
    /\ messages' = messages

EnvDrop ==
    /\ counters.drop < MaxDrop
    /\ \E m \in messages : messages' = messages \ {m}
    /\ counters' = [counters EXCEPT !.drop = @ + 1]
    /\ seen' = seen \cup {"drop"}
    /\ snapshot' = snapshot

EnvUpdate ==
    /\ EnvSnapshot \/ EnvDrop
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                   votes, leadersByEpoch, proposed, queued, appended,
                   durable, committed, applied, recovered, acked,
                   commitCertified, syncMode, syncSource, syncJustified,
                   usedTxn, syncVars>>
    /\ rollbackAuthorized' = [s \in Server |-> FALSE]

UpdateFocusedNext == AffectedActions \/ InteractionActions
OpenUpdateNext == AffectedActions \/ InteractionActions \/ EnvUpdate

UpdateFullSpec == UInit /\ [][MCNext /\ UpdateMonitor]_uVars
UpdateFocusedSpec == UInit /\ [][UpdateFocusedNext /\ UpdateMonitor]_uVars
OpenUpdateSpec == UInit /\ [][OpenUpdateNext /\ UpdateMonitor]_uVars

(* ------------------------------------------------------------------ *)
(* Update properties                                                    *)
(* ------------------------------------------------------------------ *)

\* REQ-EVIDENCE CommittedQuorumDurable
\* intent:   Every history prefix that some server holds as committed is recorded in the durable (recoverable) history of at least a quorum of servers.
\* status:   requirement
\* evidence: doc zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:117 "committed when a quorum of them acknowledge the proposal." -> commitment needs a quorum of acknowledgements
\* evidence: doc zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:119 "Acknowledgement means the server has recorded the proposal to persistent storage." -> each counted acknowledgement implies persistent recording
\* evidence: doc zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:194 "A follower will ACK the NEW_LEADER proposal after it has synced with the leader." -> the NEWLEADER ACK that commits the leader's initial history is a synced-follower acknowledgement
\* evidence: comment zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:748 (added by the update) "make sure sync the uncommitted logs before commit them (ACK NEWLEADER)" -> the buffered sync proposals must be synced to the log before the NEWLEADER ACK that commits them
\* evidence: test zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/DIFFSyncConsistencyTest.java:128-133 (added by the update) "followers ACK NEWLEADER (which makes leader think she has the quorum support, but actually not afterwards)" -> a NEWLEADER ACK must not let the leader count support that a follower failure can remove
\* evidence: impl zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:752-760 "fzk.logRequest(p.hdr, p.rec, p.digest);" then "writePacket(new QuorumPacket(Leader.ACK, newLeaderZxid, null, null), true);"
\* evidence: impl zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:88 "syncProcessor.processRequest(request);" (asynchronous enqueue, SyncRequestProcessor.java:277)
\* watch:    zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader; zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:logRequest; zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:run; zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:waitForNewLeaderAck; zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:lead
\* verified: update (2efbdfc)
\* note:     added property (no V0 counterpart). The state space reads committed and durable only.
CommittedQuorumDurable ==
    \A s \in Server :
        Len(committed[s]) > 0 =>
            Cardinality({x \in Server : IsPrefix(committed[s], durable[x])}) >= Quorum

\* REQ-EVIDENCE CommittedNeverLostByLeader
\* intent:   A leader that starts serving (broadcast) holds every entry that any server has ever held as committed, in an earlier epoch than its own.
\* status:   requirement
\* evidence: doc zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:59 "message `m` will be eventually delivered by all servers." -> a committed (delivered) entry is not lost by later leaders
\* evidence: doc zookeeper-docs/src/main/resources/markdown/zookeeperProgrammers.md:1177 "request or successful update, will never be rolled back when" -> an update a client has seen is never rolled back after server failures
\* evidence: test zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/DIFFSyncConsistencyTest.java:204-214 (added by the update) "Data inconsistency detected!" -> the next leader must still expose the transaction the previous leader served
\* watch:    zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader; zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:lead; zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FastLeaderElection.java:lookForLeader
\* verified: update (2efbdfc)
\* note:     added interaction property observed through the unchanged re-election consumer; uses the Update observer everCommitted.
CommittedNeverLostByLeader ==
    \A l \in Server :
        (up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast") =>
            \A e \in everCommitted :
                e.epoch < currentEpoch[l] => HasEntry(committed[l], e)

\* REQ-EVIDENCE NewLeaderAckAfterLogging
\* intent:   A learner that has handled NEWLEADER (and sent its ACK) has handed every buffered sync proposal to its persistence pipeline; its queued history covers the history transferred by the sync session.
\* status:   requirement
\* evidence: comment zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:748 (added by the update) "make sure sync the uncommitted logs before commit them (ACK NEWLEADER)" -> buffered sync proposals are logged before the NEWLEADER ACK
\* evidence: impl zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:752-757 "packetsNotCommitted.clear();"
\* watch:    zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader
\* verified: update (2efbdfc)
\* note:     added; in the model it is structural (the reference action empties syncBuf), its implementation check is the NewLeaderAck post-state comparison in Trace.tla.
NewLeaderAckAfterLogging ==
    \A s \in Server :
        syncStage[s] = "newleader" =>
            /\ syncBuf[s] = <<>>
            /\ \A k \in 1..Len(syncCommit[s]) : HasEntry(queued[s], syncCommit[s][k])

UTypeOK == everCommitted \subseteq Entry

\* Server identities and transaction identities are interchangeable.
UpdateSymmetry == Permutations(Server) \cup Permutations(Txn)

(* ------------------------------------------------------------------ *)
(* Discharge obligation: every omitted context step of the full MC      *)
(* model is admitted by EnvUpdate (with its frame).                     *)
(* ------------------------------------------------------------------ *)
DischargeStep == OmittedContextActions => EnvUpdate
DischargeContext == [][DischargeStep]_<<allVars, mcVars>>

(* ------------------------------------------------------------------ *)
(* Reachability canaries for the update Scenarios (expected violated).  *)
(* ------------------------------------------------------------------ *)
\* REQ-EVIDENCE NotAckBeforeDurableReached
\* intent:   Canary, expected to be violated: a leader enters broadcast while some NEWLEADER acker has not yet fsynced the transferred history.
\* status:   model-internal
\* watch:    zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader
\* verified: update (2efbdfc)
NotAckBeforeDurableReached ==
    ~\E l \in Server :
        /\ role[l] = "leading" /\ phase[l] = "broadcast"
        /\ \E s \in nlAcks[l] \ {l} : ~IsPrefix(durable[l], durable[s])

\* REQ-EVIDENCE NotSyncedHistoryCommittedReached
\* intent:   Canary, expected to be violated: a follower completes UPTODATE after a DIFF that transferred a nonempty history.
\* status:   model-internal
\* watch:    zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader
\* verified: update (2efbdfc)
NotSyncedHistoryCommittedReached ==
    ~\E s \in Server :
        /\ role[s] = "following" /\ phase[s] = "broadcast"
        /\ Len(committed[s]) > 0
        /\ "newleaderLogged" \in seen

=============================================================================
