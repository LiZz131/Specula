------------------------------ MODULE base ------------------------------
(***************************************************************************)
(* ZooKeeper Zab reference model, incremental revision for the "update"    *)
(* source commit (2efbdfc).  Source paths below are relative to            *)
(* zookeeper-server/src/main/java/org/apache/zookeeper/server/ in the       *)
(* updated tree (/work/current/.specular-output/artifact).                 *)
(*                                                                         *)
(* Incremental changes against the V0 prior (see ../modeling-brief.md §8   *)
(* and changelog.md "Incremental round 1"):                                *)
(*  - learner synchronization is split into payload receipt (CompleteSync),*)
(*    the NEWLEADER handler (SyncWithLeaderNewLeader) and the UPTODATE     *)
(*    handler (SyncWithLeaderUpToDate);                                    *)
(*  - buffered sync proposals (packetsNotCommitted) are explicit volatile  *)
(*    state (syncBuf); the updated NEWLEADER handler moves them into the   *)
(*    asynchronous persistence pipeline (queued) BEFORE the NEWLEADER ACK, *)
(*    their durability still happens later in FsyncOne;                    *)
(*  - the leader counts NEWLEADER ACKs (nlAcks) and, on activation,        *)
(*    commits/serves its whole initial history (LeaderBroadcast);          *)
(*  - repaired V0 abstractions: CompleteSync no longer makes the leader's  *)
(*    history durable at the learner instantaneously, and the unsupported  *)
(*    learner-originated QueueLearnerProposal/ObserveCommit alternatives   *)
(*    were removed from Next.                                              *)
(***************************************************************************)
EXTENDS Naturals, Integers, Sequences, FiniteSets, TLC

CONSTANTS Server, Txn, MaxEpoch, Nil

ASSUME /\ Server /= {}
       /\ Txn /= {}
       /\ MaxEpoch \in Nat \ {0}
       /\ Nil \notin Server

Role == {"looking", "leading", "following"}
Phase == {"election", "discovery", "sync", "broadcast", "offline"}
SyncModes == {"NONE", "DIFF", "TRUNC", "SNAP"}
\* UPDATE-MAP
\* code: server/quorum/Learner.java:546-760 (syncWithLeader stages)
\* update: Update!AffectedActions
SyncStages == {"idle", "payload", "newleader"}
Epoch == 0..MaxEpoch
Entry == [id : Txn, epoch : Epoch]
MsgKind == {"proposal", "ack", "commit"}
\* pos: position of a PROPOSAL's entry in the leader's history.  The
\* leader-to-learner channel is a TCP stream (LearnerHandler queuedPackets),
\* so learners receive proposals in that order; pos is 0 for ACK/COMMIT.
Message == [kind : MsgKind, from : Server, to : Server,
            id : Txn, epoch : Epoch, pos : Nat]

Quorum == (Cardinality(Server) \div 2) + 1

VARIABLES up, role, phase, leaderOf,
          acceptedEpoch, currentEpoch,
          votes, leadersByEpoch,
          proposed, queued, appended, durable, committed, applied,
          snapshot, recovered,
          acked, commitCertified, messages,
          syncMode, syncSource, syncJustified,
          usedTxn, rollbackAuthorized,
          \* UPDATE-MAP
          \* code: server/quorum/Learner.java:555-557,646-667,743-760
          \* update: Update!AffectedActions / Update!EnvUpdate (frame: unchanged by the environment)
          syncBuf, syncCommit, syncStage, nlAcks

allVars == <<up, role, phase, leaderOf,
             acceptedEpoch, currentEpoch,
             votes, leadersByEpoch,
             proposed, queued, appended, durable, committed, applied,
             snapshot, recovered,
             acked, commitCertified, messages,
             syncMode, syncSource, syncJustified,
             usedTxn, rollbackAuthorized,
             syncBuf, syncCommit, syncStage, nlAcks>>

syncVars == <<syncBuf, syncCommit, syncStage, nlAcks>>

IsPrefix(a, b) == Len(a) <= Len(b) /\ SubSeq(b, 1, Len(a)) = a
EntryFor(id, ep) == [id |-> id, epoch |-> ep]
TxnIds(h) == {h[k].id : k \in 1..Len(h)}
LastEpoch(h) == IF Len(h) = 0 THEN 0 ELSE h[Len(h)].epoch
LastId(h) == IF Len(h) = 0 THEN Nil ELSE h[Len(h)].id
Suffix(h, n) == SubSeq(h, n + 1, Len(h))
\* Longest common prefix of two histories (prefix equality is monotone, so
\* the first index where they differ is unique).
CommonPrefix(a, b) ==
    LET n == CHOOSE k \in 0..Len(a) :
               /\ k <= Len(b)
               /\ SubSeq(a, 1, k) = SubSeq(b, 1, k)
               /\ (k = Len(a) \/ k = Len(b) \/ a[k + 1] /= b[k + 1])
    IN SubSeq(a, 1, n)
HasEntry(h, ent) == \E k \in 1..Len(h) : h[k] = ent
Longer(a, b) == IF Len(a) >= Len(b) THEN a ELSE b
\* A server's persistence pipeline has no queued/appended entry left to fsync.
Drained(s) == /\ proposed[s] = durable[s]
              /\ queued[s] = durable[s]
              /\ appended[s] = durable[s]

ResetRollback == rollbackAuthorized' = [s \in Server |-> FALSE]

Init ==
    /\ up = [s \in Server |-> TRUE]
    /\ role = [s \in Server |-> "looking"]
    /\ phase = [s \in Server |-> "election"]
    /\ leaderOf = [s \in Server |-> Nil]
    /\ acceptedEpoch = [s \in Server |-> 0]
    /\ currentEpoch = [s \in Server |-> 0]
    /\ votes = [s \in Server |-> {}]
    /\ leadersByEpoch = [e \in Epoch |-> {}]
    /\ proposed = [s \in Server |-> <<>>]
    /\ queued = [s \in Server |-> <<>>]
    /\ appended = [s \in Server |-> <<>>]
    /\ durable = [s \in Server |-> <<>>]
    /\ committed = [s \in Server |-> <<>>]
    /\ applied = [s \in Server |-> <<>>]
    /\ snapshot = [s \in Server |-> <<>>]
    /\ recovered = [s \in Server |-> <<>>]
    /\ acked = [t \in Txn |-> {}]
    /\ commitCertified = [t \in Txn |-> FALSE]
    /\ messages = {}
    /\ syncMode = [s \in Server |-> "NONE"]
    /\ syncSource = [s \in Server |-> Nil]
    /\ syncJustified = [s \in Server |-> FALSE]
    /\ usedTxn = {}
    /\ rollbackAuthorized = [s \in Server |-> FALSE]
    /\ syncBuf = [s \in Server |-> <<>>]
    /\ syncCommit = [s \in Server |-> <<>>]
    /\ syncStage = [s \in Server |-> "idle"]
    /\ nlAcks = [s \in Server |-> {}]

(* FastLeaderElection.lookForLeader: logical round and self vote.
   QuorumPeer.run (quorum/QuorumPeer.java:1468-1491) leaves FOLLOWING/LEADING
   through follower.shutdown()/leader.shutdown(); the learner's in-memory
   sync buffers (Learner.java:555-557 locals) are dropped. The persistence
   pipeline is not touched here: a RUNNING server flushes it on shutdown, and
   in the updated code a learner that fails between NEWLEADER and UPTODATE
   keeps its INITIAL-state processors running (ZooKeeperServer.java:784-786,
   LearnerZooKeeperServer.java:155-158), so AppendOne/FsyncOne remain enabled. *)
BeginElection(s) ==
    /\ up[s]
    /\ acceptedEpoch[s] < MaxEpoch
    /\ role' = [role EXCEPT ![s] = "looking"]
    /\ phase' = [phase EXCEPT ![s] = "election"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = Nil]
    /\ votes' = [votes EXCEPT ![s] = {s}]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ syncSource' = [syncSource EXCEPT ![s] = Nil]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = FALSE]
    /\ syncBuf' = [syncBuf EXCEPT ![s] = <<>>]
    /\ syncCommit' = [syncCommit EXCEPT ![s] = <<>>]
    /\ syncStage' = [syncStage EXCEPT ![s] = "idle"]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, leadersByEpoch,
                    proposed, queued, appended, durable, committed, applied,
                    snapshot, recovered, acked, commitCertified, messages,
                    usedTxn, nlAcks>>
    /\ ResetRollback

(* FLE totalOrderPredicate: epoch, then last zxid/log length, then id. *)
HistoryAtLeast(candidate, voter) ==
    \/ currentEpoch[candidate] > currentEpoch[voter]
    \/ /\ currentEpoch[candidate] = currentEpoch[voter]
       /\ Len(durable[candidate]) >= Len(durable[voter])

CastVote(voter, candidate) ==
    /\ up[voter] /\ up[candidate]
    /\ role[voter] = "looking"
    /\ HistoryAtLeast(candidate, voter)
    /\ votes' = [votes EXCEPT ![candidate] = @ \cup {voter}]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncVars>>
    /\ ResetRollback

(* FLE quorum decision followed by Leader.getEpochToPropose.
   A new Leader object owns a fresh newLeaderProposal ack set
   (quorum/Leader.java:434,610).  The candidate's previous-role
   ZooKeeperServer.shutdown flushed its SyncRequestProcessor
   (SyncRequestProcessor.java:254-260) before LOOKING, so the leader's
   pipeline is drained when lead() loads its history (Leader.java:579-604). *)
WinElection(candidate) ==
    /\ up[candidate]
    /\ role[candidate] = "looking"
    /\ Cardinality(votes[candidate]) >= Quorum
    /\ acceptedEpoch[candidate] < MaxEpoch
    /\ Drained(candidate)
    /\ LET ep == acceptedEpoch[candidate] + 1 IN
       /\ leadersByEpoch[ep] = {}
       /\ role' = [role EXCEPT ![candidate] = "leading"]
       /\ phase' = [phase EXCEPT ![candidate] = "discovery"]
       /\ leaderOf' = [leaderOf EXCEPT ![candidate] = candidate]
       /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![candidate] = ep]
       /\ leadersByEpoch' = [leadersByEpoch EXCEPT ![ep] = {candidate}]
    /\ nlAcks' = [nlAcks EXCEPT ![candidate] = {}]
    /\ UNCHANGED <<up, currentEpoch, votes, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncBuf, syncCommit, syncStage>>
    /\ ResetRollback

(* QuorumPeer main loop switches a learner to FOLLOWING before Zab discovery;
   only a LOOKING peer can decide to follow (QuorumPeer.java:1468-1476 after
   FastLeaderElection.lookForLeader). *)
FollowLeader(s, l) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "looking"
    /\ role[l] = "leading"
    /\ role' = [role EXCEPT ![s] = "following"]
    /\ phase' = [phase EXCEPT ![s] = "discovery"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = l]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, votes, leadersByEpoch,
                    proposed, queued, appended, durable, committed, applied,
                    snapshot, recovered, acked, commitCertified, messages,
                    syncMode, syncSource, syncJustified, usedTxn, syncVars>>
    /\ ResetRollback

(* Learner.registerWithLeader persists acceptedEpoch before ACKEPOCH. *)
AcceptEpoch(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "discovery"
    /\ leaderOf[s] \in Server
    /\ acceptedEpoch[s] < acceptedEpoch[leaderOf[s]]
    /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![s] = acceptedEpoch[leaderOf[s]]]
    /\ UNCHANGED <<up, role, phase, leaderOf, currentEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncVars>>
    /\ ResetRollback

(* Leader.waitForEpochAck completes after a participant quorum
   (Leader.java:657); lead() then persists the current epoch (:658), enters
   SYNCHRONIZATION (:660) and counts its own NEWLEADER ack through
   waitForNewLeaderAck(self.getId(), ...) (:663, :1569). *)
FinishDiscovery(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "discovery"
    /\ Cardinality({s \in Server : up[s] /\ acceptedEpoch[s] = acceptedEpoch[l]}) >= Quorum
    /\ currentEpoch' = [currentEpoch EXCEPT ![l] = acceptedEpoch[l]]
    /\ phase' = [phase EXCEPT ![l] = "sync"]
    /\ nlAcks' = [nlAcks EXCEPT ![l] = {l}]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncBuf, syncCommit, syncStage>>
    /\ ResetRollback

DiffAllowed(s, l) == IsPrefix(durable[s], durable[l])
TruncAllowed(s, l) == IsPrefix(durable[l], durable[s])

(* QuorumPeer exposes SYNCHRONIZATION before the mode packet is consumed. *)
EnterSyncPhase(s, l) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "following" /\ leaderOf[s] = l
    /\ phase[s] = "discovery" /\ phase[l] = "sync"
    \* Learner.registerWithLeader persists the proposed epoch before the
    \* learner can consume a synchronization directive.
    /\ acceptedEpoch[s] = acceptedEpoch[l]
    /\ phase' = [phase EXCEPT ![s] = "sync"]
    /\ syncSource' = [syncSource EXCEPT ![s] = l]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncJustified,
                    usedTxn, syncVars>>
    /\ ResetRollback

(* LearnerHandler.syncFollower chooses DIFF/TRUNC/SNAP under the DB log lock. *)
SelectSync(s, l, mode) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "following" /\ leaderOf[s] = l
    /\ phase[s] = "sync" /\ phase[l] = "sync"
    /\ syncSource[s] = l
    /\ syncStage[s] = "idle"
    \* one sync directive per learner session (Learner.java:558-603)
    /\ syncMode[s] = "NONE"
    /\ mode \in SyncModes \ {"NONE"}
    /\ IF mode = "DIFF" THEN DiffAllowed(s, l)
       ELSE IF mode = "TRUNC" THEN TruncAllowed(s, l)
       ELSE ~(DiffAllowed(s, l) \/ TruncAllowed(s, l)) \/ durable[s] = <<>>
    /\ syncMode' = [syncMode EXCEPT ![s] = mode]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncSource, syncJustified,
                    usedTxn, syncVars>>
    /\ ResetRollback

(* History the leader transfers in a sync session: its whole (drained)
   history plus outstanding proposals forwarded by startForwarding. *)
SyncTarget(l) == proposed[l]
(* Prefix the leader marks committed in the session.  A leader still in
   SYNCHRONIZATION sends its whole loaded committedLog as PROPOSAL+COMMIT
   pairs; an established leader commits only its committed prefix and
   forwards outstanding proposals without COMMIT. *)
SyncCommitTarget(l) == IF phase[l] = "broadcast" THEN committed[l] ELSE proposed[l]
(* Part of the target that is installed or persisted before NEWLEADER
   without going through FollowerZooKeeperServer.logRequest. *)
SyncBase(s, l, mode) ==
    CASE mode = "DIFF"  -> durable[s]
      [] mode = "TRUNC" -> Longer(CommonPrefix(durable[s], SyncTarget(l)),
                                  SyncCommitTarget(l))
      [] OTHER          -> SyncCommitTarget(l)

(* Learner.syncWithLeader consumes the selected directive and the leader's
   payload packets up to (not including) NEWLEADER.
   - DIFF (Learner.java:561-564): snapshotNeeded=false, so writeToTxnLog is
     true (:619); PROPOSALs go to packetsNotCommitted (:621-647) and COMMITs
     to packetsCommitted (:666-667).  Nothing is persisted here.
   - TRUNC (:587-598): the log is truncated immediately (durable rollback);
     COMMITs before NEWLEADER are applied in memory (:655-664).
   - SNAP (:565-585): the leader's data tree is deserialized in memory; it
     becomes durable only by the NEWLEADER snapshot (:739-741).
   In every mode the not-yet-committed proposals stay in the volatile
   packetsNotCommitted buffer (syncBuf).  The V0 prior instead copied the
   leader's durable history into durable[s] here; that is repaired. *)
\* UPDATE-MAP
\* code: server/quorum/Learner.java:546-711 (payload loop, unchanged; V0 abstraction repaired)
\* update: Update!AffectedActions (MCCompleteSync)
CompleteSync(s) ==
    /\ up[s] /\ phase[s] = "sync"
    /\ syncSource[s] \in Server
    /\ syncMode[s] \in SyncModes \ {"NONE"}
    /\ syncStage[s] = "idle"
    \* A new FollowerZooKeeperServer's log starts after the previous
    \* session's processors were flushed (see BeginElection comment).
    /\ Drained(s)
    /\ LET l == syncSource[s]
           mode == syncMode[s]
           T == SyncTarget(l)
           CT == SyncCommitTarget(l)
           base == SyncBase(s, l, mode)
           trunc == CommonPrefix(durable[s], T)
       IN
       /\ up[l] /\ role[l] = "leading"
       \* The selected sync and NEWLEADER exchange are bound to one epoch;
       \* reusing the same leader identity after restart is not sufficient.
       /\ acceptedEpoch[s] = acceptedEpoch[l]
       /\ IsPrefix(base, T)
       /\ IF mode = "DIFF" THEN IsPrefix(durable[s], T) ELSE TRUE
       /\ syncBuf' = [syncBuf EXCEPT ![s] = Suffix(T, Len(base))]
       /\ syncCommit' = [syncCommit EXCEPT ![s] = CT]
       /\ syncStage' = [syncStage EXCEPT ![s] = "payload"]
       /\ IF mode = "TRUNC"
          THEN /\ durable' = [durable EXCEPT ![s] = trunc]
               /\ appended' = [appended EXCEPT ![s] = trunc]
               /\ queued' = [queued EXCEPT ![s] = trunc]
               /\ proposed' = [proposed EXCEPT ![s] = trunc]
          ELSE UNCHANGED <<durable, appended, queued, proposed>>
       /\ IF mode = "DIFF"
          THEN UNCHANGED <<committed, applied>>
          ELSE /\ committed' = [committed EXCEPT ![s] = committed[l]]
               /\ applied' = [applied EXCEPT ![s] = applied[l]]
       /\ recovered' = [recovered EXCEPT ![s] = T]
       /\ syncJustified' = [syncJustified EXCEPT ![s] = TRUE]
       /\ rollbackAuthorized' = [x \in Server |-> x = s]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, snapshot, acked, commitCertified,
                    messages, syncMode, syncSource, usedTxn, nlAcks>>

(* Learner.syncWithLeader NEWLEADER case, updated revision
   (Learner.java:726-761):
     - SNAP/TRUNC take the sync snapshot (:739-741);
     - setCurrentEpoch(newEpoch) persists the epoch (:743);
     - setSyncMode(NONE) and zk.startupWithoutServing() now happen here
       (:749-751; previously after UPTODATE, old Learner.java:753-755);
     - every buffered packetsNotCommitted proposal is handed to
       FollowerZooKeeperServer.logRequest (:752-757), which only appends it
       to pendingTxns and to the SyncRequestProcessor queue
       (FollowerZooKeeperServer.java:86-88, SyncRequestProcessor.java:277);
       append/fsync happen later on the SyncThread (AppendOne/FsyncOne);
     - the NEWLEADER ACK is written (:760) without waiting for that fsync.
   The leader counts the ACK in waitForNewLeaderAck only while its
   quorum is not yet formed and the ACK zxid names its epoch
   (Leader.java:1547-1573, LearnerHandler.java:623).  Counting at send time
   admits every later receive order. *)
\* UPDATE-MAP
\* code: server/quorum/Learner.java:726-761; server/ZooKeeperServer.java:669-704
\* update: Update!AffectedActions (MCSyncWithLeaderNewLeader)
SyncWithLeaderNewLeader(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncStage[s] = "payload"
    /\ syncSource[s] \in Server
    /\ LET l == syncSource[s]
           mode == syncMode[s]
           \* SNAP: the snapshot persists the installed/committed tree;
           \* TRUNC: the snapshot persists in-memory commits beyond the log.
           newDur == CASE mode = "SNAP" -> syncCommit[s]
                       [] mode = "TRUNC" -> Longer(durable[s], syncCommit[s])
                       [] OTHER -> durable[s]
           logged == newDur \o syncBuf[s]
       IN
       /\ IsPrefix(durable[s], newDur) \/ mode = "SNAP"
       /\ durable' = [durable EXCEPT ![s] = newDur]
       /\ appended' = [appended EXCEPT ![s] = newDur]
       /\ queued' = [queued EXCEPT ![s] = logged]
       /\ proposed' = [proposed EXCEPT ![s] = logged]
       /\ snapshot' = IF mode \in {"SNAP", "TRUNC"}
                      THEN [snapshot EXCEPT ![s] = applied[s]]
                      ELSE snapshot
       /\ currentEpoch' = [currentEpoch EXCEPT ![s] = acceptedEpoch[s]]
       /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
       /\ syncBuf' = [syncBuf EXCEPT ![s] = <<>>]
       /\ syncStage' = [syncStage EXCEPT ![s] = "newleader"]
       /\ nlAcks' = IF /\ up[l] /\ role[l] = "leading" /\ phase[l] = "sync"
                       /\ acceptedEpoch[l] = acceptedEpoch[s]
                    THEN [nlAcks EXCEPT ![l] = @ \cup {s}]
                    ELSE nlAcks
       /\ rollbackAuthorized' = [x \in Server |-> x = s /\ mode = "SNAP"]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, votes,
                    leadersByEpoch, committed, applied, recovered, acked,
                    commitCertified, messages, syncSource, syncJustified,
                    usedTxn, syncCommit>>

(* Learner.syncWithLeader UPTODATE case and its epilogue, updated revision
   (Learner.java:711-725, 764-785): the learner leaves the packet loop,
   ACKs UPTODATE, zk.startServing() switches the already started server to
   RUNNING (:767, ZooKeeperServer.java:677-680), then packetsCommitted are
   committed in order (:783-785, FollowerZooKeeperServer.commit).  The
   leader sends UPTODATE only after its NEWLEADER quorum formed and its own
   server started (LearnerHandler.java:623-648).  Follower.followLeader then
   publishes BROADCAST. *)
\* UPDATE-MAP
\* code: server/quorum/Learner.java:764-785; server/ZooKeeperServer.java:677-680
\* update: Update!AffectedActions (MCSyncWithLeaderUpToDate)
SyncWithLeaderUpToDate(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncStage[s] = "newleader"
    /\ syncSource[s] \in Server
    /\ currentEpoch[s] = acceptedEpoch[s]
    /\ LET l == syncSource[s] IN
       /\ up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
       /\ acceptedEpoch[l] = acceptedEpoch[s]
    /\ IsPrefix(syncCommit[s], proposed[s])
    /\ committed' = [committed EXCEPT ![s] = syncCommit[s]]
    /\ phase' = [phase EXCEPT ![s] = "broadcast"]
    /\ syncCommit' = [syncCommit EXCEPT ![s] = <<>>]
    /\ syncStage' = [syncStage EXCEPT ![s] = "idle"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    applied, snapshot, recovered, acked, commitCertified,
                    messages, syncMode, syncSource, syncJustified, usedTxn,
                    syncBuf, nlAcks>>
    /\ ResetRollback

(* Leader.lead: after waitForNewLeaderAck observes a NEWLEADER ack quorum
   (Leader.java:663, :1569-1573), startZkServer() starts serving the
   leader's data tree (:688, :1497-1530), whose content is its whole loaded
   history (loadData / fastForwardDataBase, ZooKeeperServer.java:845), and
   lead() publishes BROADCAST (:712).  The initial history therefore becomes
   committed and visible at the leader in this step. *)
\* UPDATE-MAP
\* code: server/quorum/Leader.java:663-712 (unchanged consumer of NEWLEADER ACKs)
\* update: Update!InteractionActions (MCLeaderBroadcast)
LeaderBroadcast(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "sync"
    /\ Cardinality(nlAcks[l]) >= Quorum
    /\ IsPrefix(committed[l], durable[l])
    /\ phase' = [phase EXCEPT ![l] = "broadcast"]
    /\ committed' = [committed EXCEPT ![l] = durable[l]]
    /\ applied' = [applied EXCEPT ![l] = durable[l]]
    /\ commitCertified' = [t \in Txn |-> commitCertified[t] \/ t \in TxnIds(durable[l])]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, snapshot, recovered, acked, messages, syncMode,
                    syncSource, syncJustified, usedTxn, syncVars>>
    /\ ResetRollback

(* ProposalRequestProcessor calls propose before enqueuing local disk sync. *)
Propose(l, t) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
    /\ t \in Txn \ usedTxn
    /\ LET ent == EntryFor(t, currentEpoch[l]) IN
       /\ proposed' = [proposed EXCEPT ![l] = Append(@, ent)]
       /\ queued' = [queued EXCEPT ![l] = Append(@, ent)]
       /\ messages' = messages \cup
             {[kind |-> "proposal", from |-> l, to |-> s,
               id |-> t, epoch |-> currentEpoch[l],
               pos |-> Len(proposed[l]) + 1] :
                 s \in Server \ {l}}
    /\ usedTxn' = usedTxn \cup {t}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, appended, durable, committed,
                    applied, snapshot, recovered, acked, commitCertified,
                    syncMode, syncSource, syncJustified, syncVars>>
    /\ ResetRollback

(* Follower.processPacket PROPOSAL -> FollowerZooKeeperServer.logRequest.
   Proposals arrive in the leader's order over the TCP stream (FIFO, pos).
   LearnerHandler.startForwarding forwards only proposals after the learner's
   sync point, so a proposal already transferred by the sync payload is not
   delivered again: such a model message is consumed without effect. *)
ReceiveProposal(m) ==
    /\ m \in messages /\ m.kind = "proposal"
    /\ up[m.to] /\ role[m.to] = "following" /\ phase[m.to] = "broadcast"
    /\ leaderOf[m.to] = m.from
    \* A learner's packet stream reaches broadcast only for its synchronized
    \* current epoch; a stale connection cannot enqueue a later-epoch proposal.
    /\ currentEpoch[m.to] = m.epoch
    /\ LET ent == EntryFor(m.id, m.epoch) IN
       IF m.pos <= Len(proposed[m.to])
       THEN UNCHANGED <<proposed, queued>>
       ELSE /\ m.pos = Len(proposed[m.to]) + 1
            /\ proposed' = [proposed EXCEPT ![m.to] = Append(@, ent)]
            /\ queued' = [queued EXCEPT ![m.to] = Append(@, ent)]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, appended, durable, committed,
                    applied, snapshot, recovered, acked, commitCertified,
                    syncMode, syncSource, syncJustified, usedTxn, syncVars>>
    /\ ResetRollback

(* SyncRequestProcessor append writes the txn stream but has not fsynced it
   (SyncRequestProcessor.java:181). *)
AppendOne(s) ==
    /\ up[s] /\ Len(appended[s]) < Len(queued[s])
    /\ LET ent == queued[s][Len(appended[s]) + 1] IN
       appended' = [appended EXCEPT ![s] = Append(@, ent)]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncVars>>
    /\ ResetRollback

(* FileTxnLog.commit forces an appended entry (SyncRequestProcessor.java:235);
   ACK is only created afterward (SendAckRequestProcessor on a learner, the
   leader's AckRequestProcessor on a leader).  A learner whose session ended
   still fsyncs; its ACK has no live leader connection and is not modeled. *)
FsyncOne(s) ==
    /\ up[s] /\ Len(durable[s]) < Len(appended[s])
    /\ LET ent == appended[s][Len(durable[s]) + 1] IN
       /\ durable' = [durable EXCEPT ![s] = Append(@, ent)]
       /\ IF role[s] = "leading"
          THEN /\ acked' = [acked EXCEPT ![ent.id] = @ \cup {s}]
               /\ messages' = messages
          ELSE IF leaderOf[s] \in Server
          THEN /\ acked' = acked
               /\ messages' = messages \cup
                    {[kind |-> "ack", from |-> s, to |-> leaderOf[s],
                      id |-> ent.id, epoch |-> ent.epoch, pos |-> 0]}
          ELSE UNCHANGED <<acked, messages>>
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    committed, applied, snapshot, recovered,
                    commitCertified, syncMode, syncSource,
                    syncJustified, usedTxn, syncVars>>
    /\ ResetRollback

DeliverAck(m) ==
    /\ m \in messages /\ m.kind = "ack" /\ up[m.to]
    /\ acked' = [acked EXCEPT ![m.id] = @ \cup {m.from}]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered,
                    commitCertified, syncMode, syncSource, syncJustified,
                    usedTxn, syncVars>>
    /\ ResetRollback

(* Leader.tryToCommit requires quorum ACKs and in-order outstanding proposals. *)
Commit(l, t) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
    /\ Len(committed[l]) < Len(proposed[l])
    /\ LET ent == proposed[l][Len(committed[l]) + 1] IN
       /\ ent.id = t
       /\ Cardinality(acked[t]) >= Quorum
       /\ committed' = [committed EXCEPT ![l] = Append(@, ent)]
       /\ commitCertified' = [commitCertified EXCEPT ![t] = TRUE]
       /\ messages' = messages \cup
            {[kind |-> "commit", from |-> l, to |-> s,
              id |-> t, epoch |-> ent.epoch, pos |-> 0] : s \in Server \ {l}}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, applied, snapshot, recovered, acked, syncMode,
                    syncSource, syncJustified, usedTxn, syncVars>>
    /\ ResetRollback

(* A COMMIT packet is a certificate of a leader-side quorum decision. *)
ReceiveCommit(m) ==
    /\ m \in messages /\ m.kind = "commit" /\ up[m.to]
    /\ role[m.to] = "following" /\ leaderOf[m.to] = m.from
    \* COMMITs reaching a learner before UPTODATE are part of the sync
    \* payload (packetsCommitted); broadcast COMMITs are processed after it.
    /\ phase[m.to] = "broadcast"
    /\ currentEpoch[m.to] = m.epoch
    /\ IF HasEntry(committed[m.to], EntryFor(m.id, m.epoch))
       THEN UNCHANGED <<committed, commitCertified>>
       ELSE /\ Len(committed[m.to]) < Len(proposed[m.to])
            /\ proposed[m.to][Len(committed[m.to]) + 1] = EntryFor(m.id, m.epoch)
            /\ committed' = [committed EXCEPT ![m.to] = Append(@, EntryFor(m.id, m.epoch))]
            /\ commitCertified' = [commitCertified EXCEPT ![m.id] = TRUE]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, applied, snapshot, recovered, acked, syncMode,
                    syncSource, syncJustified, usedTxn, syncVars>>
    /\ ResetRollback

(* FinalRequestProcessor applies only a certified, in-order commit. *)
ApplyOne(s) ==
    /\ up[s] /\ Len(applied[s]) < Len(committed[s])
    /\ LET ent == committed[s][Len(applied[s]) + 1] IN
       /\ commitCertified[ent.id]
       /\ applied' = [applied EXCEPT ![s] = Append(@, ent)]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncVars>>
    /\ ResetRollback

(* Snapshot captures an applied prefix and is named by lastProcessedZxid. *)
TakeSnapshot(s) ==
    /\ up[s] /\ snapshot[s] /= applied[s]
    /\ snapshot' = [snapshot EXCEPT ![s] = applied[s]]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncVars>>
    /\ ResetRollback

(* Crash drops non-durable queues and learner buffers; the snapshot is the
   safe visible restart prefix.  A NEWLEADER ACK already written before the
   crash stays counted by the leader (Leader.java:1569 never removes acks). *)
Crash(s) ==
    /\ up[s]
    /\ up' = [up EXCEPT ![s] = FALSE]
    /\ role' = [role EXCEPT ![s] = "looking"]
    /\ phase' = [phase EXCEPT ![s] = "offline"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = Nil]
    /\ proposed' = [proposed EXCEPT ![s] = durable[s]]
    /\ queued' = [queued EXCEPT ![s] = durable[s]]
    /\ appended' = [appended EXCEPT ![s] = durable[s]]
    /\ committed' = [committed EXCEPT ![s] = snapshot[s]]
    /\ applied' = [applied EXCEPT ![s] = snapshot[s]]
    /\ recovered' = [recovered EXCEPT ![s] = <<>>]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ syncSource' = [syncSource EXCEPT ![s] = Nil]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = FALSE]
    /\ syncBuf' = [syncBuf EXCEPT ![s] = <<>>]
    /\ syncCommit' = [syncCommit EXCEPT ![s] = <<>>]
    /\ syncStage' = [syncStage EXCEPT ![s] = "idle"]
    \* election votes for s are volatile FLE round state
    /\ votes' = [votes EXCEPT ![s] = {}]
    /\ rollbackAuthorized' = [x \in Server |-> x = s]
    /\ UNCHANGED <<acceptedEpoch, currentEpoch, leadersByEpoch,
                    durable, snapshot, acked, commitCertified, messages,
                    usedTxn, nlAcks>>

(* restore() loads snapshot then replays durable log into tentative recovery state. *)
Restart(s) ==
    /\ ~up[s]
    /\ up' = [up EXCEPT ![s] = TRUE]
    /\ phase' = [phase EXCEPT ![s] = "election"]
    /\ recovered' = [recovered EXCEPT ![s] = durable[s]]
    /\ UNCHANGED <<role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, acked, commitCertified,
                    messages, syncMode, syncSource, syncJustified, usedTxn,
                    syncVars>>
    /\ ResetRollback

DropMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, syncMode, syncSource, syncJustified,
                    usedTxn, syncVars>>
    /\ ResetRollback

Next ==
    \/ \E s \in Server : BeginElection(s)
    \/ \E voter, candidate \in Server : CastVote(voter, candidate)
    \/ \E s \in Server : WinElection(s)
    \/ \E s, l \in Server : FollowLeader(s, l)
    \/ \E s \in Server : AcceptEpoch(s)
    \/ \E l \in Server : FinishDiscovery(l)
    \/ \E s, l \in Server : EnterSyncPhase(s, l)
    \/ \E s, l \in Server, mode \in SyncModes \ {"NONE"} : SelectSync(s, l, mode)
    \/ \E s \in Server : CompleteSync(s)
    \/ \E s \in Server : SyncWithLeaderNewLeader(s)
    \/ \E s \in Server : SyncWithLeaderUpToDate(s)
    \/ \E l \in Server : LeaderBroadcast(l)
    \/ \E l \in Server, t \in Txn : Propose(l, t)
    \/ \E m \in messages : ReceiveProposal(m)
    \/ \E s \in Server : AppendOne(s)
    \/ \E s \in Server : FsyncOne(s)
    \/ \E m \in messages : DeliverAck(m)
    \/ \E l \in Server, t \in Txn : Commit(l, t)
    \/ \E m \in messages : ReceiveCommit(m)
    \/ \E s \in Server : ApplyOne(s)
    \/ \E s \in Server : TakeSnapshot(s)
    \/ \E s \in Server : Crash(s)
    \/ \E s \in Server : Restart(s)
    \/ \E m \in messages : DropMessage(m)

Spec == Init /\ [][Next]_allVars

\* REQ-EVIDENCE TypeOK
\* intent:   Every model variable always holds a value of its declared type.
\* status:   model-internal
\* watch:    none (type invariant of the model itself)
\* verified: update (2efbdfc); extended for syncBuf/syncCommit/syncStage/nlAcks
\* review:   ok
TypeOK ==
    /\ up \in [Server -> BOOLEAN]
    /\ role \in [Server -> Role]
    /\ phase \in [Server -> Phase]
    /\ leaderOf \in [Server -> (Server \cup {Nil})]
    /\ acceptedEpoch \in [Server -> Epoch]
    /\ currentEpoch \in [Server -> Epoch]
    /\ votes \in [Server -> SUBSET Server]
    /\ leadersByEpoch \in [Epoch -> SUBSET Server]
    /\ proposed \in [Server -> Seq(Entry)]
    /\ queued \in [Server -> Seq(Entry)]
    /\ appended \in [Server -> Seq(Entry)]
    /\ durable \in [Server -> Seq(Entry)]
    /\ committed \in [Server -> Seq(Entry)]
    /\ applied \in [Server -> Seq(Entry)]
    /\ snapshot \in [Server -> Seq(Entry)]
    /\ recovered \in [Server -> Seq(Entry)]
    /\ acked \in [Txn -> SUBSET Server]
    /\ commitCertified \in [Txn -> BOOLEAN]
    /\ messages \subseteq Message
    /\ syncMode \in [Server -> SyncModes]
    /\ syncSource \in [Server -> (Server \cup {Nil})]
    /\ syncJustified \in [Server -> BOOLEAN]
    /\ usedTxn \subseteq Txn
    /\ rollbackAuthorized \in [Server -> BOOLEAN]
    /\ syncBuf \in [Server -> Seq(Entry)]
    /\ syncCommit \in [Server -> Seq(Entry)]
    /\ syncStage \in [Server -> SyncStages]
    /\ nlAcks \in [Server -> SUBSET Server]

\* REQ-EVIDENCE ElectionSafety
\* intent:   At most one server ever takes leadership of any given epoch.
\* status:   requirement
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:130 "Leadership activation will ensure that only one leader uses a given epoch" -> at most one leader per epoch
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:195 "will only ACK a NEW_LEADER proposal with a given zxid from a single server" -> a follower ACKs the NEW_LEADER proposal for a given zxid (epoch) from only one server (mechanism toward one leader per epoch)
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:513 "since we have already acked an epoch equal to the leaders, we cannot ack" -> a follower acknowledges a given epoch at most once
\* evidence: history 1a556bd1 (message) "getEpochToPropose should check if lastAcceptedEpoch is greater or equal than epoch" -> a proposed epoch must exceed, not merely equal, a follower's last accepted epoch (mechanism against epoch reuse)
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/Zab1_0Test.java:213 testLastAcceptedEpoch "New proposed epoch is wrong" -> the proposed epoch exceeds the accepted epoch a connecting follower reports (6 gives 7)
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:1401 "if (lastAcceptedEpoch >= epoch) {"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:517 "wrappedEpochBytes.putInt(-1);"
\* watch:    source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:getEpochToPropose; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:waitForEpochAck; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:registerWithLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerHandler.java:run; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FastLeaderElection.java:lookForLeader
\* verified: base; update (2efbdfc) — watch locations untouched by the update, unaffected control property
\* note:     searched docs and main sources for "one leader", "single leader", "same epoch", "unique epoch"; zookeeperInternals.md:130 is the only direct statement. No Zab paper text exists in /work, so no protocol-type evidence is cited. The Learner.java:513 comment and commit 1a556bd1 describe the mechanism that yields the property rather than the property itself.
\* review:   intent said "established as leader" but the formula counts every server that won the election for an epoch, so it now says "takes leadership"; the :195, 1a556bd1 and testLastAcceptedEpoch arrows were narrowed to what each quote literally states.
ElectionSafety == \A e \in Epoch : Cardinality(leadersByEpoch[e]) <= 1

\* REQ-EVIDENCE OneActiveLeaderPerEpoch
\* intent:   At any moment, at most one running server is leading in any given epoch.
\* status:   requirement
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:130 "Leadership activation will ensure that only one leader uses a given epoch" -> at most one leader uses an epoch
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:246 "there is only one active leader at a time" -> at most one active leader (taken per epoch, see note)
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:211 "no other leader will be able to get a quorum of followers" -> a second leader cannot become established while one holds its quorum
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:760 "if (!tickSkip && !syncedAckSet.hasAllQuorums()) {"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:1401 "if (lastAcceptedEpoch >= epoch) {"
\* watch:    source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:lead; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:getEpochToPropose; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:run; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:registerWithLeader
\* verified: base; update (2efbdfc) — watch locations untouched by the update, unaffected control property
\* note:     zookeeperInternals.md:278 describes two servers that simultaneously think they are the leader, so the "one active leader at a time" sentence (line 246) is relied on only in its per-epoch reading. Searched main sources for "two leaders", "multiple leaders", "single leader": no further statement found.
\* review:   ok
OneActiveLeaderPerEpoch ==
    \A e \in Epoch :
        Cardinality({s \in Server : up[s] /\ role[s] = "leading"
                                    /\ acceptedEpoch[s] = e}) <= 1

\* REQ-EVIDENCE CommittedHistoriesPrefix
\* intent:   For any two servers, one server's sequence of committed transactions is a prefix of the other's.
\* status:   requirement
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:63 "message `a` will be delivered before `b` by all" -> all servers commit/deliver transactions in the same order
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:59 "message `m` will be eventually delivered by all servers." -> every server eventually delivers a message that one server delivered (none is skipped for good)
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:234 "COMMITs are processed in order." -> each follower commits in the leader's order
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:891 "make sure that ops are committed in order." -> the leader commits in proposal order
\* evidence: test zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/DIFFSyncConsistencyTest.java:213 (added by the update) "Data inconsistency detected!" -> a transaction visible at the old leader must be visible at the next leader
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:103 "if (firstElementZxid != zxid) {"
\* watch:    source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:tryToCommit; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:processAck; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerHandler.java:syncFollower; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerHandler.java:queueCommittedProposals; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:commit; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Follower.java:processPacket
\* verified: update (2efbdfc) — watch Learner.syncWithLeader touched; kept (requirement), keep evidence in spec/invariant-evidence.json
\* note:     no single source states the prefix relation; it follows from Total order (zookeeperInternals.md:61-64) together with Reliable delivery (zookeeperInternals.md:57-59). FollowerResyncConcurrencyTest.java:608 (helper verifyState, called from testResyncByDiffAfterFollowerCrashes) was not counted: it asserts only that leader and follower hold the same number of ephemerals for a session.
\* review:   removed the FollowerResyncConcurrencyTest:608 line, whose assertion compares only per-session ephemeral counts and so supports no part of the prefix intent, and narrowed the line-59 arrow to what Reliable delivery states.
CommittedHistoriesPrefix ==
    \A a, b \in Server : IsPrefix(committed[a], committed[b]) \/
                          IsPrefix(committed[b], committed[a])

\* REQ-EVIDENCE ApplyRequiresCommitCertificate
\* intent:   A server applies only transactions that a quorum has committed, and applies them in its commit order.
\* status:   requirement
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:902 "in order to be committed, a proposal must be accepted by a quorum." -> a commit is backed by a quorum certificate
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:117 "committed when a quorum of them acknowledge the proposal." -> committed means quorum-acknowledged
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:235 "message when that proposal is committed." -> a follower delivers (applies) a proposal only once it is committed
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/CommitProcessor.java:70 "Write requests must be processed in zxid order" -> applied sequence follows commit order
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/Zab1_0Test.java:655 testNormalFollowerRun "The change should not have happened yet, since we haven't committed" -> a proposed transaction is not applied before its COMMIT arrives (assertion at line 656, one scenario)
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:663 "zk.processTxn(pif.hdr, pif.rec);"
\* watch:    source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/CommitProcessor.java:run; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/FinalRequestProcessor.java:processRequest; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:tryToCommit; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:commit; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnSnapLog.java:restore
\* verified: update (2efbdfc) — watch Learner.syncWithLeader touched; kept (requirement), keep evidence in spec/invariant-evidence.json
\* note:     the doc sentence spans zookeeperInternals.md:234-235 ("Followers deliver a proposal message when that proposal is committed."); only the line-235 part is quoted. FollowerZooKeeperServer.java:95 (@param contract of commit) was not counted: it requires a COMMIT to match the head of pendingTxns, which is about commit order, not about what is applied.
\* review:   removed the FollowerZooKeeperServer.java:95 contract line, which constrains which zxid a COMMIT may name and supports no part of the apply intent, and narrowed the Zab1_0Test:655 arrow to the one scenario it asserts.
ApplyRequiresCommitCertificate ==
    \A s \in Server :
        /\ IsPrefix(applied[s], committed[s])
        /\ \A k \in 1..Len(applied[s]) : commitCertified[applied[s][k].id]

\* REQ-EVIDENCE PipelinePrefix
\* intent:   On every server the fsynced, written and queued sequences are successive prefixes of the proposal sequence (so the fsynced log follows proposal order), and the snapshot is a prefix of the applied sequence.
\* status:   mixed
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:229 "has been written to non-volatile storage, all messages that were proposed before" -> the fsynced log is a prefix of the proposal order
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:245 "see and record proposals in order" -> each server records proposals in proposal order
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:226 "Followers process messages in the order they are received." -> a follower processes proposals in arrival order (for followers, the recorded log follows proposal order)
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperAdmin.md:2593 "last committed transaction at the start of the snapshot" -> a snapshot is labelled with a transaction already applied when it starts
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:181 "if (!si.isThrottled() && zks.getZKDatabase().append(si)) {"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:235 "zks.getZKDatabase().commit();"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnSnapLog.java:468 "long lastZxid = dataTree.lastProcessedZxid;"
\* watch:    source/zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:run; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:flush; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnLog.java:append; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnLog.java:commit; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/ProposalRequestProcessor.java:processRequest; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:logRequest; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java:takeSnapshot; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnSnapLog.java:save
\* verified: update (2efbdfc) — not on a watch line, but the update adds a new caller of FollowerZooKeeperServer.logRequest (Learner.java:752-757), so the property is affected; kept, keep evidence in spec/invariant-evidence.json
\* clause durableInProposalOrder: requirement — what conjuncts 1-3 jointly imply, that the fsynced log is a prefix of the proposal sequence: zookeeperInternals.md:229, :245, :226.
\* clause intermediateStages: impl-abstraction — conjuncts 1-3 as written, i.e. separate queued and written-but-unsynced stages each a prefix of the one before: only impl (SyncRequestProcessor.java queuedRequests, append at :181, flush/commit at :235).
\* clause snapshotWithinApplied: requirement — conjunct 4: zookeeperAdmin.md:2588-2594 (snapshot named by the last committed transaction at its start, contents taken from the data tree).
\* note:     the separate queued and written (appended) stages are named only in the implementation (SyncRequestProcessor queuedRequests/toFlush); the docs speak of in-order recording as a whole. zookeeperAdmin.md:2589-2600 calls snapshots fuzzy (content may match no tree that existed); the quote supports only that a snapshot never reaches beyond applied updates.
\* review:   status changed from requirement to mixed: the separate queue and written-but-unsynced stages are backed only by impl (the :226 arrow had generalized "followers process messages in order" to every stage), so only the fsync-order and snapshot parts stay requirement.
PipelinePrefix ==
    \A s \in Server :
        /\ IsPrefix(durable[s], appended[s])
        /\ IsPrefix(appended[s], queued[s])
        /\ IsPrefix(queued[s], proposed[s])
        /\ IsPrefix(snapshot[s], applied[s])

\* REQ-EVIDENCE EpochHistoryConsistency
\* intent:   On every server the current epoch never exceeds the accepted epoch, and the last fsynced log entry carries no epoch later than the accepted epoch.
\* status:   mixed
\* evidence: history 19d85670 (message) "ZooKeeper not starting because acceptedEpoch is less than the currentEpoch" -> an accepted epoch below the current epoch is a defect
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/Zab1_0Test.java:615 testNormalFollowerRun "assertEquals(0, f.self.getCurrentEpoch());" -> after ACKEPOCH the current epoch (0) lags the accepted epoch (1, line 614)
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/Zab1_0Test.java:749 testNormalFollowerRunWithDiff "assertEquals(0, f.self.getCurrentEpoch());" -> same ordering in the DIFF-sync conversation (accepted 1 at line 748)
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:1142 "if (acceptedEpoch < currentEpoch) {"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:1122 "if (epochOfZxid > currentEpoch) {"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:521 "is less than accepted epoch,"
\* watch:    source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:loadDataBase; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:setCurrentEpoch; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:setAcceptedEpoch; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:registerWithLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:lead; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:getEpochToPropose
\* verified: update (2efbdfc) — watch Learner.syncWithLeader touched; kept, keep evidence in spec/invariant-evidence.json
\* clause currentEpochAtMostAccepted: requirement — commit 19d85670 (ZOOKEEPER-2307) treats acceptedEpoch < currentEpoch as a startup-blocking defect; Zab1_0Test:614-615 and 748-749 assert accepted advances before current.
\* clause logEpochAtMostAccepted: unknown — only impl: QuorumPeer.loadDataBase (line 1122) refuses to start when the last zxid's epoch exceeds the current epoch; no doc, comment, test or commit message states the rule.
\* note:     the update moves no epoch write (setCurrentEpoch stays at Learner.java:743 before logging/ACK).
\* review:   intent said no logged transaction carries a later epoch, but the formula bounds only the epoch of the last fsynced entry, so the intent was narrowed to that; evidence, clauses and statuses checked and kept.
EpochHistoryConsistency ==
    /\ \A s \in Server : currentEpoch[s] <= acceptedEpoch[s]
    /\ \A s \in Server : LastEpoch(durable[s]) <= acceptedEpoch[s]

\* REQ-EVIDENCE SyncCompletionJustified
\* intent:   A follower in the broadcast phase has completed synchronization with its leader, has an identified leader, and has set its current epoch equal to its accepted epoch.
\* status:   mixed
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:194 "A follower will ACK the NEW_LEADER proposal after it has synced with the leader." -> a follower has synced with the leader before it ACKs NEW_LEADER
\* evidence: history f8f15de5 (message) "setCurrentEpoch should be done upon receipt of NEWLEADER (before acking it)" -> current epoch equals the new (accepted) epoch before the follower leaves sync
\* evidence: history 148c2cd6 (message) "Fix data inconsistency due to NEWLEADER being sent too early" -> NEWLEADER, which ends sync, must follow the complete sync payload
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/QuorumPeerMainTest.java:1179 testInconsistentDueToNewLeaderOrder "start follower A, after it's in broadcast state, make sure" -> a broadcasting follower holds the leader's synced data
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/Zab1_0Test.java:637 testNormalFollowerRun "assertEquals(1, f.self.getCurrentEpoch());" -> after the NEWLEADER ACK current epoch equals accepted epoch (1, line 636)
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/Zab1_0Test.java:780 testNormalFollowerRunWithDiff "assertEquals(1, f.self.getCurrentEpoch());" -> same after a DIFF sync (accepted 1, line 779)
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Follower.java:109 "syncWithLeader(newEpochZxid);"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:743 "self.setCurrentEpoch(newEpoch);"
\* watch:    source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Follower.java:followLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:registerWithLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerHandler.java:run; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:waitForNewLeaderAck
\* verified: update (2efbdfc) — watch Learner.syncWithLeader touched; kept, keep evidence in spec/invariant-evidence.json
\* clause syncedBeforeBroadcast: requirement — zookeeperInternals.md:194; commit 148c2cd6 (ZOOKEEPER-3104); QuorumPeerMainTest:1179 testInconsistentDueToNewLeaderOrder.
\* clause epochsAlignedInBroadcast: requirement — commit f8f15de5 (ZOOKEEPER-1282) message; Zab1_0Test:636-637 and 779-780.
\* clause leaderKnown: model-internal — well-formedness of the leaderOf bookkeeping; only impl backs it (Follower.java:107 setLeaderAddressAndId before sync).
\* review:   narrowed the :194 arrow from "leaves synchronization" to the NEW_LEADER ACK that the doc actually orders after syncing; other evidence, clauses and statuses checked and kept.
SyncCompletionJustified ==
    \A s \in Server :
        (role[s] = "following" /\ phase[s] = "broadcast") =>
          /\ syncJustified[s]
          /\ leaderOf[s] \in Server
          /\ currentEpoch[s] = acceptedEpoch[s]

\* REQ-EVIDENCE NoIllegalRollback
\* intent:   A server's durable log, committed prefix and applied prefix never shrink, except when the server crashes or installs its leader's history during synchronization.
\* status:   mixed
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:183 "the leader will tell the follower to discard `U`." -> the sync-time exception: uncommitted proposals a follower logged are discarded when the leader tells it to
\* evidence: contract source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/TxnLog.java:83 "truncate the log to get in sync with the" -> log truncation exists to get in sync with the leader
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:119 "Acknowledgement means the server has recorded the proposal to persistent storage." -> an acknowledged proposal is recorded in persistent storage, so it is not lost
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperOver.md:168 "client will never see an older view of the system even if the" -> a serving server's applied state does not move backwards
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperProgrammers.md:1177 "request or successful update, will never be rolled back when" -> updates a client has seen are never rolled back when recovering from server failures
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/test/TruncateTest.java:225 testTruncate "as a result /12 is the first of the truncated znodes to check for" -> the permitted exception: an unquorumed log suffix is truncated when syncing with the leader
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:591 "boolean truncated = zk.getZKDatabase().truncateLog(qp.getZxid());"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/ZKDatabase.java:600 "clear();"
\* watch:    source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/ZKDatabase.java:truncateLog; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/ZKDatabase.java:deserializeSnapshot; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/ZKDatabase.java:loadDataBase; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnSnapLog.java:truncateLog; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnLog.java:truncate; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerHandler.java:syncFollower
\* verified: update (2efbdfc) — watch Learner.syncWithLeader touched; kept, keep evidence in spec/invariant-evidence.json
\* clause durableNoRollback: requirement — zookeeperInternals.md:119 and 182-183, TxnLog.java:83 contract; TruncateTest:225 shows the sync-time exception.
\* clause appliedNoRollback: requirement — zookeeperOver.md:166-171 (Single System Image, Reliability) and zookeeperProgrammers.md:1176-1178.
\* clause committedNoRollback: unknown — only impl (Learner.syncWithLeader packetsCommitted, FollowerZooKeeperServer.commit pendingTxns); no statement covers a learner's committed-but-unapplied prefix.
\* review:   narrowed three arrows to what the quotes state (line 183 has the leader direct the discard of U but no "only", line 119 defines ACK as persistent recording, line 1177 covers updates a client has seen); clause statuses kept.
NoIllegalRollback ==
    \A s \in Server :
       /\ (Len(durable'[s]) >= Len(durable[s]) \/ rollbackAuthorized'[s])
       /\ (Len(committed'[s]) >= Len(committed[s]) \/ rollbackAuthorized'[s])
       /\ (Len(applied'[s]) >= Len(applied[s]) \/ rollbackAuthorized'[s])

\* REQ-EVIDENCE HistoryPositionsMonotonicExceptRecovery -> alias of [][NoIllegalRollback]_allVars; see REQ-EVIDENCE NoIllegalRollback
\* review:   ok
HistoryPositionsMonotonicExceptRecovery == [][NoIllegalRollback]_allVars

Safety == TypeOK /\ ElectionSafety /\ OneActiveLeaderPerEpoch /\
          CommittedHistoriesPrefix /\ ApplyRequiresCommitCertificate /\
          PipelinePrefix /\ EpochHistoryConsistency /\ SyncCompletionJustified

\* All voting-server identities are interchangeable in the finite models.
\* TLC's permutation quotient removes only renamed copies of the same state.
ModelSymmetry == Permutations(Server)

\* Canonical TLC runs are exhaustive through this explicit finite execution
\* depth (inherited from V0; budget-limited in the incremental campaigns).
CanonicalDepthBound == TLCGet("level") <= 23

=============================================================================
