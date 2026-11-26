------------------------------ MODULE base ------------------------------
(***************************************************************************)
(* Reference model of the ZooKeeper Zab implementation, revision "update" *)
(* (neutral synthetic commit 2efbdfc).  Revised incrementally from the V0  *)
(* exact-old prior (spec/prior-v0/base.tla).                               *)
(*                                                                         *)
(* Incremental revision summary (see spec/changelog.md, Round U):          *)
(*  - Learner synchronization is split at the real learner-thread          *)
(*    boundaries of Learner.syncWithLeader: directive/contents (SelectSync)*)
(*    -> NEWLEADER processing (LearnerNewLeader) -> NEWLEADER ACK          *)
(*    (LearnerAckNewLeader) -> UPTODATE/serving (EnterBroadcast).          *)
(*  - Synced DIFF contents are volatile learner buffers (syncPending =     *)
(*    packetsNotCommitted) until handed to the log pipeline.  The update   *)
(*    hands them off at NEWLEADER, before the ACK (NewLeaderLogsPending =  *)
(*    TRUE); the old revision did it after UPTODATE (FALSE, control only). *)
(*  - The leader starts broadcasting on a quorum of NEWLEADER ACKs         *)
(*    (Leader.waitForNewLeaderAck) and then serves/commits its whole       *)
(*    initial history (Leader.lead -> zk.loadData, startZkServer).         *)
(***************************************************************************)
EXTENDS Naturals, Integers, Sequences, FiniteSets, TLC

CONSTANTS Server, Txn, MaxEpoch, Nil,
          \* TRUE  = updated Learner.java:744-760 (hand off packetsNotCommitted
          \*         to the log pipeline at NEWLEADER, before the ACK).
          \* FALSE = exact-old Learner.java:741-755 (hand off after UPTODATE);
          \*         used only by the old-behaviour attribution control cfg.
          NewLeaderLogsPending

ASSUME /\ Server /= {}
       /\ Txn /= {}
       /\ MaxEpoch \in Nat \ {0}
       /\ Nil \notin Server
       /\ NewLeaderLogsPending \in BOOLEAN

Role == {"looking", "leading", "following"}
Phase == {"election", "discovery", "sync", "broadcast", "offline"}
SyncModes == {"NONE", "DIFF", "TRUNC", "SNAP"}
\* Learner.syncWithLeader progress of the learner thread:
\*  idle      - not in a synchronization exchange
\*  selected  - DIFF/TRUNC/SNAP directive and contents consumed (startForwarding done)
\*  newleader - NEWLEADER processed: snapshot (SNAP/TRUNC), currentEpoch persisted,
\*              and (update) buffered proposals handed to the log pipeline
\*  acked     - NEWLEADER ACK written to the leader
\*  uptodate  - UPTODATE processed, server serving
LearnerStages == {"idle", "selected", "newleader", "acked", "uptodate"}
Epoch == 0..MaxEpoch
Entry == [id : Txn, epoch : Epoch]
CommitRecord == [entry : Entry, cepoch : Epoch]
MsgKind == {"proposal", "ack", "commit"}
Message == [kind : MsgKind, from : Server, to : Server,
            id : Txn, epoch : Epoch]

Quorum == (Cardinality(Server) \div 2) + 1

VARIABLES up, role, phase, leaderOf,
          acceptedEpoch, currentEpoch,
          votes, leadersByEpoch,
          proposed, queued, appended, durable, committed, applied,
          snapshot, recovered,
          acked, commitCertified, messages,
          syncMode, syncSource, syncJustified,
          usedTxn, rollbackAuthorized,
          \* UPDATE-MAP: learner/leader NEWLEADER bookkeeping (see header)
          syncPending,    \* Learner.syncWithLeader packetsNotCommitted (volatile)
          learnerStage,   \* learner-thread position in syncWithLeader
          nlAcks,         \* Leader newLeaderProposal ack set (volatile, per leadership)
          everCommitted   \* history variable: entries a leader committed/served, with epoch

allVars == <<up, role, phase, leaderOf,
             acceptedEpoch, currentEpoch,
             votes, leadersByEpoch,
             proposed, queued, appended, durable, committed, applied,
             snapshot, recovered,
             acked, commitCertified, messages,
             syncMode, syncSource, syncJustified,
             usedTxn, rollbackAuthorized,
             syncPending, learnerStage, nlAcks, everCommitted>>

IsPrefix(a, b) == Len(a) <= Len(b) /\ SubSeq(b, 1, Len(a)) = a
EntryFor(id, ep) == [id |-> id, epoch |-> ep]
TxnIds(h) == {h[k].id : k \in 1..Len(h)}
HasEntry(h, ent) == \E k \in 1..Len(h) : h[k] = ent
LastEpoch(h) == IF Len(h) = 0 THEN 0 ELSE h[Len(h)].epoch
LastId(h) == IF Len(h) = 0 THEN Nil ELSE h[Len(h)].id
Suffix(h, n) == SubSeq(h, n + 1, Len(h))

\* A role transition starts only after the previous role's request pipeline was
\* drained: ZooKeeperServer.shutdown -> SyncRequestProcessor.shutdown joins and
\* flush()es (SyncRequestProcessor.java:254-259) before QuorumPeer runs the next
\* election/role; a crash instead resets the pipeline to durable (Crash).
Drained(s) == proposed[s] = durable[s]

\* The leader's initial history of its epoch: entries it had logged before the
\* epoch (Leader.lead -> zk.loadData, Leader.java:593).  New-epoch proposals
\* carry the leader's current epoch.
InitialHistory(l) == SelectSeq(proposed[l], LAMBDA x : x.epoch < acceptedEpoch[l])

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
    /\ syncPending = [s \in Server |-> <<>>]
    /\ learnerStage = [s \in Server |-> "idle"]
    /\ nlAcks = [s \in Server |-> {}]
    /\ everCommitted = {}

(* FastLeaderElection.lookForLeader: logical round and self vote.  Leaving a  *)
(* role discards the learner thread's local buffers (syncWithLeader locals)   *)
(* and the leader's in-memory NEWLEADER ack set.                              *)
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
    /\ syncPending' = [syncPending EXCEPT ![s] = <<>>]
    /\ learnerStage' = [learnerStage EXCEPT ![s] = "idle"]
    /\ nlAcks' = [nlAcks EXCEPT ![s] = {}]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, leadersByEpoch,
                    proposed, queued, appended, durable, committed, applied,
                    snapshot, recovered, acked, commitCertified, messages,
                    usedTxn, everCommitted>>
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
                    syncJustified, usedTxn, syncPending, learnerStage,
                    nlAcks, everCommitted>>
    /\ ResetRollback

(* FLE quorum decision followed by Leader.getEpochToPropose. *)
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
                    syncJustified, usedTxn, syncPending, learnerStage,
                    everCommitted>>
    /\ ResetRollback

(* QuorumPeer main loop switches a learner to FOLLOWING before Zab discovery. *)
FollowLeader(s, l) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[l] = "leading"
    /\ Drained(s)
    /\ role' = [role EXCEPT ![s] = "following"]
    /\ phase' = [phase EXCEPT ![s] = "discovery"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = l]
    /\ syncPending' = [syncPending EXCEPT ![s] = <<>>]
    /\ learnerStage' = [learnerStage EXCEPT ![s] = "idle"]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, votes, leadersByEpoch,
                    proposed, queued, appended, durable, committed, applied,
                    snapshot, recovered, acked, commitCertified, messages,
                    syncMode, syncSource, syncJustified, usedTxn, nlAcks,
                    everCommitted>>
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
                    syncJustified, usedTxn, syncPending, learnerStage, nlAcks,
                    everCommitted>>
    /\ ResetRollback

\* StateSummary.isMoreRecentThan (StateSummary.java:42-44) over
\* (currentEpoch, last logged zxid); log length approximates the zxid order as in
\* HistoryAtLeast.
AheadOf(s, l) ==
    \/ currentEpoch[s] > currentEpoch[l]
    \/ /\ currentEpoch[s] = currentEpoch[l]
       /\ Len(durable[s]) > Len(durable[l])

(* Leader.waitForEpochAck completes after a participant quorum.  Before the    *)
(* quorum forms, an ACKEPOCH whose summary is more recent than the leader's    *)
(* aborts the leader ("Follower is ahead of the leader", Leader.java:1442-1455);*)
(* the aborted leader can only re-enter election (BeginElection).              *)
\* Round U model-checking repair (Case B): guard was missing in the prior suite.
FinishDiscovery(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "discovery"
    /\ Cardinality({s \in Server : up[s] /\ acceptedEpoch[s] = acceptedEpoch[l]}) >= Quorum
    /\ \A s \in Server :
          (/\ s /= l /\ up[s] /\ role[s] = "following" /\ leaderOf[s] = l
           /\ acceptedEpoch[s] = acceptedEpoch[l]) => ~AheadOf(s, l)
    /\ currentEpoch' = [currentEpoch EXCEPT ![l] = acceptedEpoch[l]]
    /\ phase' = [phase EXCEPT ![l] = "sync"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncPending, learnerStage, nlAcks,
                    everCommitted>>
    /\ ResetRollback

\* The leader's sync source history: LearnerHandler.syncFollower serves the
\* leader's committed log, which Leader.lead -> zk.loadData rebuilt from every
\* logged transaction (Leader.java:593, ZKDatabase.loadDataBase).
LeaderHistory(l) == proposed[l]
DiffAllowed(s, l) == IsPrefix(durable[s], LeaderHistory(l))
TruncAllowed(s, l) == IsPrefix(LeaderHistory(l), durable[s])

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
                    usedTxn, syncPending, learnerStage, nlAcks, everCommitted>>
    /\ ResetRollback

(* LearnerHandler.syncFollower (LearnerHandler.java:775-933) chooses           *)
(* DIFF/TRUNC/SNAP under the DB log lock and queues the directive and history  *)
(* before startForwarding; Learner.syncWithLeader (Learner.java:560-707)       *)
(* consumes it before NEWLEADER:                                               *)
(*  DIFF : PROPOSAL(+COMMIT) pairs buffered in packetsNotCommitted             *)
(*         (writeToTxnLog=true, Learner.java:614,641,667) -> syncPending.      *)
(*  TRUNC: ZKDatabase.truncateLog truncates the on-disk log immediately and    *)
(*         reloads the tree (Learner.java:586-597) -> durable shrinks.         *)
(*  SNAP : deserializeSnapshot replaces only the in-memory tree                *)
(*         (Learner.java:565-583) -> tentative recovered history; it becomes   *)
(*         durable only through takeSnapshot at NEWLEADER.                     *)
(* The tentative tree is not served until UPTODATE (state INITIAL), so it is  *)
(* kept out of committed/applied.                                              *)
\* UPDATE-MAP
\* code: Learner.java:syncWithLeader directive + PROPOSAL/COMMIT buffering (unchanged)
\* update: Update!InteractionActions (producer of the buffered history)
SelectSync(s, l, mode) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "following" /\ leaderOf[s] = l
    /\ phase[s] = "sync" /\ phase[l] = "sync"
    /\ syncSource[s] = l
    /\ learnerStage[s] = "idle"
    /\ mode \in SyncModes \ {"NONE"}
    /\ IF mode = "DIFF" THEN DiffAllowed(s, l)
       ELSE IF mode = "TRUNC" THEN TruncAllowed(s, l)
       ELSE ~(DiffAllowed(s, l) \/ TruncAllowed(s, l)) \/ durable[s] = <<>>
    /\ syncMode' = [syncMode EXCEPT ![s] = mode]
    /\ learnerStage' = [learnerStage EXCEPT ![s] = "selected"]
    /\ LET H == LeaderHistory(l) IN
       CASE mode = "DIFF" ->
              /\ syncPending' = [syncPending EXCEPT ![s] = Suffix(H, Len(durable[s]))]
              /\ UNCHANGED <<proposed, queued, appended, durable, recovered>>
              /\ ResetRollback
         [] mode = "TRUNC" ->
              /\ durable' = [durable EXCEPT ![s] = H]
              /\ appended' = [appended EXCEPT ![s] = H]
              /\ queued' = [queued EXCEPT ![s] = H]
              /\ proposed' = [proposed EXCEPT ![s] = H]
              /\ recovered' = [recovered EXCEPT ![s] = H]
              /\ syncPending' = [syncPending EXCEPT ![s] = <<>>]
              /\ rollbackAuthorized' = [x \in Server |-> x = s]
         [] OTHER ->
              /\ recovered' = [recovered EXCEPT ![s] = H]
              /\ syncPending' = [syncPending EXCEPT ![s] = <<>>]
              /\ UNCHANGED <<proposed, queued, appended, durable>>
              /\ ResetRollback
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, committed, applied, snapshot, acked,
                    commitCertified, messages, syncSource, syncJustified,
                    usedTxn, nlAcks, everCommitted>>

(* Learner.syncWithLeader NEWLEADER case (Learner.java:726-758).              *)
(*  SNAP/TRUNC: zk.takeSnapshot persists the installed tree (:739-741).       *)
(*  self.setCurrentEpoch(newEpoch) persists the epoch (:743).                 *)
(*  UPDATE (NewLeaderLogsPending): setSyncMode(NONE), startupWithoutServing,  *)
(*  and fzk.logRequest for every packetsNotCommitted entry, then clear        *)
(*  (:749-758).  logRequest only enqueues to SyncRequestProcessor             *)
(*  (FollowerZooKeeperServer.java:82-89): the entries become queued, not      *)
(*  durable.  OLD: none of this happens before the ACK.                       *)
\* UPDATE-MAP
\* code: Learner.java:744-758 (new) vs old Learner.java:743-746
\* update: Update!AffectedActions (MCLearnerNewLeader)
LearnerNewLeader(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ learnerStage[s] = "selected"
    /\ syncSource[s] \in Server
    /\ LET l == syncSource[s] IN
       /\ up[l] /\ role[l] = "leading"
       \* NEWLEADER is bound to the epoch the learner registered for.
       /\ acceptedEpoch[s] = acceptedEpoch[l]
    /\ LET base == IF syncMode[s] = "SNAP" THEN recovered[s] ELSE queued[s]
           snapRollback == syncMode[s] = "SNAP"
       IN
       /\ IF syncMode[s] = "SNAP"
          THEN \* takeSnapshot(syncSnapshot=true): the tree becomes the durable history
               /\ durable' = [durable EXCEPT ![s] = recovered[s]]
               /\ appended' = [appended EXCEPT ![s] = recovered[s]]
          ELSE UNCHANGED <<durable, appended>>
       /\ IF NewLeaderLogsPending
          THEN /\ queued' = [queued EXCEPT ![s] = base \o syncPending[s]]
               /\ proposed' = [proposed EXCEPT ![s] = base \o syncPending[s]]
               /\ syncPending' = [syncPending EXCEPT ![s] = <<>>]
               /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
          ELSE /\ queued' = [queued EXCEPT ![s] = base]
               /\ proposed' = [proposed EXCEPT ![s] = base]
               /\ UNCHANGED <<syncPending, syncMode>>
       /\ rollbackAuthorized' = [x \in Server |-> x = s /\ snapRollback]
    /\ currentEpoch' = [currentEpoch EXCEPT ![s] = acceptedEpoch[s]]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = TRUE]
    /\ learnerStage' = [learnerStage EXCEPT ![s] = "newleader"]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, votes,
                    leadersByEpoch, committed, applied, snapshot, recovered,
                    acked, commitCertified, messages, syncSource, usedTxn,
                    nlAcks, everCommitted>>

(* Learner.java:760 writePacket(ACK newLeaderZxid, flush=true), received by   *)
(* LearnerHandler.java:611-623 -> Leader.waitForNewLeaderAck (:1547-1575).    *)
(* The ACK is not conditioned on the SyncRequestProcessor flush.              *)
\* UPDATE-MAP
\* code: Learner.java:760 (new; old :746)
\* update: Update!AffectedActions (MCLearnerAckNewLeader)
LearnerAckNewLeader(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ learnerStage[s] = "newleader"
    /\ leaderOf[s] \in Server
    /\ LET l == leaderOf[s] IN
       /\ up[l] /\ role[l] = "leading"
       /\ acceptedEpoch[l] = acceptedEpoch[s]
       /\ nlAcks' = [nlAcks EXCEPT ![l] = @ \cup {s}]
    /\ learnerStage' = [learnerStage EXCEPT ![s] = "acked"]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncPending, everCommitted>>
    /\ ResetRollback

(* Learner.syncWithLeader after UPTODATE (Learner.java:711-725, 763-785) and  *)
(* Follower.followLeader BROADCAST (Follower.java:109-110).  UPTODATE is only *)
(* queued after waitForNewLeaderAck and waitForStartup (LearnerHandler.java:  *)
(* 623-648).  Remaining packetsNotCommitted are logged; OLD also clears the   *)
(* sync mode and starts the processors here (zk.startup), NEW only            *)
(* startServing().  packetsCommitted are delivered later by ObserveCommit.    *)
\* UPDATE-MAP
\* code: Learner.java:763-785 (new startServing; old setSyncMode+startup)
\* update: Update!AffectedActions (MCEnterBroadcast)
EnterBroadcast(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ learnerStage[s] = "acked"
    /\ syncJustified[s] /\ currentEpoch[s] = acceptedEpoch[s]
    /\ leaderOf[s] \in Server
    /\ LET l == leaderOf[s] IN
       /\ up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
       /\ acceptedEpoch[l] = acceptedEpoch[s]
    /\ phase' = [phase EXCEPT ![s] = "broadcast"]
    /\ queued' = [queued EXCEPT ![s] = @ \o syncPending[s]]
    /\ proposed' = [proposed EXCEPT ![s] = @ \o syncPending[s]]
    /\ syncPending' = [syncPending EXCEPT ![s] = <<>>]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ learnerStage' = [learnerStage EXCEPT ![s] = "uptodate"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, appended, durable, committed, applied,
                    snapshot, recovered, acked, commitCertified, messages,
                    syncSource, syncJustified, usedTxn, nlAcks, everCommitted>>
    /\ ResetRollback

(* Leader.waitForNewLeaderAck forms a quorum including the leader's own ACK   *)
(* (Leader.java:663), then startZkServer -> zk.startup() serves the tree that *)
(* zk.loadData rebuilt from the whole log (Leader.java:593, 688, 1497-1526):  *)
(* the initial history becomes committed/served.                              *)
\* UPDATE-MAP
\* code: Leader.java:657-688 (unchanged consumer of the NEWLEADER ACK)
\* update: Update!InteractionActions (MCLeaderBroadcast)
LeaderBroadcast(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "sync"
    /\ Cardinality(nlAcks[l] \cup {l}) >= Quorum
    /\ phase' = [phase EXCEPT ![l] = "broadcast"]
    /\ committed' = [committed EXCEPT ![l] = proposed[l]]
    /\ applied' = [applied EXCEPT ![l] = proposed[l]]
    /\ commitCertified' = [t \in Txn |-> commitCertified[t] \/ t \in TxnIds(proposed[l])]
    /\ everCommitted' = everCommitted \cup
         {[entry |-> proposed[l][k], cepoch |-> acceptedEpoch[l]] : k \in 1..Len(proposed[l])}
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, snapshot, recovered, acked, messages, syncMode,
                    syncSource, syncJustified, usedTxn, syncPending,
                    learnerStage, nlAcks>>
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
               id |-> t, epoch |-> currentEpoch[l]] :
                 s \in Server \ {l}}
    /\ usedTxn' = usedTxn \cup {t}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, appended, durable, committed,
                    applied, snapshot, recovered, acked, commitCertified,
                    syncMode, syncSource, syncJustified, syncPending,
                    learnerStage, nlAcks, everCommitted>>
    /\ ResetRollback

(* Follower.processPacket PROPOSAL -> FollowerZooKeeperServer.logRequest in   *)
(* broadcast; during synchronization (after startForwarding) a forwarded      *)
(* PROPOSAL is buffered in packetsNotCommitted (Learner.java:620-642).        *)
ReceiveProposal(m) ==
    /\ m \in messages /\ m.kind = "proposal"
    /\ up[m.to] /\ role[m.to] = "following"
    /\ leaderOf[m.to] = m.from
    /\ LET ent == EntryFor(m.id, m.epoch)
           s == m.to IN
       \/ /\ phase[s] = "broadcast"
          \* A learner's packet stream reaches broadcast only for its synchronized
          \* current epoch; a stale connection cannot enqueue a later-epoch proposal.
          /\ currentEpoch[s] = m.epoch
          /\ ~HasEntry(proposed[s], ent)
          /\ proposed' = [proposed EXCEPT ![s] = Append(@, ent)]
          /\ queued' = [queued EXCEPT ![s] = Append(@, ent)]
          /\ UNCHANGED syncPending
       \/ /\ phase[s] = "sync"
          /\ learnerStage[s] \in {"selected", "newleader", "acked"}
          /\ acceptedEpoch[s] = m.epoch
          /\ ~HasEntry(proposed[s] \o syncPending[s], ent)
          /\ syncPending' = [syncPending EXCEPT ![s] = Append(@, ent)]
          /\ UNCHANGED <<proposed, queued>>
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, appended, durable, committed,
                    applied, snapshot, recovered, acked, commitCertified,
                    syncMode, syncSource, syncJustified, usedTxn,
                    learnerStage, nlAcks, everCommitted>>
    /\ ResetRollback

(* After UPTODATE the learner commits packetsCommitted in order               *)
(* (Learner.java:783-785 -> FollowerZooKeeperServer.commit :97-110); a COMMIT  *)
(* is only ever sent for an entry its leader committed.                       *)
ObserveCommit(s, t, ep) ==
    /\ up[s] /\ role[s] = "following"
    /\ phase[s] = "broadcast"
    /\ Len(committed[s]) < Len(proposed[s])
    /\ proposed[s][Len(committed[s]) + 1] = EntryFor(t, ep)
    /\ \E c \in everCommitted : c.entry = EntryFor(t, ep)
    /\ committed' = [committed EXCEPT ![s] = Append(@, EntryFor(t, ep))]
    /\ commitCertified' = [commitCertified EXCEPT ![t] = TRUE]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, applied, snapshot, recovered, acked, messages,
                    syncMode, syncSource, syncJustified, usedTxn,
                    syncPending, learnerStage, nlAcks, everCommitted>>
    /\ ResetRollback

(* SyncRequestProcessor append writes the txn stream but has not fsynced it. *)
AppendOne(s) ==
    /\ up[s] /\ Len(appended[s]) < Len(queued[s])
    /\ LET ent == queued[s][Len(appended[s]) + 1] IN
       appended' = [appended EXCEPT ![s] = Append(@, ent)]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncPending, learnerStage, nlAcks,
                    everCommitted>>
    /\ ResetRollback

(* FileTxnLog.commit forces an appended entry; ACK is only created afterward. *)
FsyncOne(s) ==
    /\ up[s] /\ Len(durable[s]) < Len(appended[s])
    /\ LET ent == appended[s][Len(durable[s]) + 1] IN
       /\ durable' = [durable EXCEPT ![s] = Append(@, ent)]
       /\ IF role[s] = "leading"
          THEN /\ acked' = [acked EXCEPT ![ent.id] = @ \cup {s}]
               /\ messages' = messages
          ELSE /\ acked' = acked
               \* SendAckRequestProcessor writes an ACK to the current leader; a
               \* processor still flushing after its role ended (shutdown join/flush,
               \* or the update's not-yet-serving orphan) has no live connection.
               /\ messages' = IF leaderOf[s] \in Server
                              THEN messages \cup
                                   {[kind |-> "ack", from |-> s, to |-> leaderOf[s],
                                     id |-> ent.id, epoch |-> ent.epoch]}
                              ELSE messages
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    committed, applied, snapshot, recovered,
                    commitCertified, syncMode, syncSource,
                    syncJustified, usedTxn, syncPending, learnerStage, nlAcks,
                    everCommitted>>
    /\ ResetRollback

DeliverAck(m) ==
    /\ m \in messages /\ m.kind = "ack" /\ up[m.to]
    /\ acked' = [acked EXCEPT ![m.id] = @ \cup {m.from}]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered,
                    commitCertified, syncMode, syncSource, syncJustified,
                    usedTxn, syncPending, learnerStage, nlAcks, everCommitted>>
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
              id |-> t, epoch |-> ent.epoch] : s \in Server \ {l}}
       /\ everCommitted' = everCommitted \cup
            {[entry |-> ent, cepoch |-> acceptedEpoch[l]]}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, applied, snapshot, recovered, acked, syncMode,
                    syncSource, syncJustified, usedTxn, syncPending,
                    learnerStage, nlAcks>>
    /\ ResetRollback

(* A COMMIT packet is a certificate of a leader-side quorum decision. *)
ReceiveCommit(m) ==
    /\ m \in messages /\ m.kind = "commit" /\ up[m.to]
    /\ role[m.to] = "following" /\ leaderOf[m.to] = m.from
    /\ phase[m.to] = "broadcast"
    /\ currentEpoch[m.to] = m.epoch
    /\ Len(committed[m.to]) < Len(proposed[m.to])
    /\ proposed[m.to][Len(committed[m.to]) + 1] = EntryFor(m.id, m.epoch)
    /\ committed' = [committed EXCEPT ![m.to] = Append(@, EntryFor(m.id, m.epoch))]
    /\ commitCertified' = [commitCertified EXCEPT ![m.id] = TRUE]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, applied, snapshot, recovered, acked, syncMode,
                    syncSource, syncJustified, usedTxn, syncPending,
                    learnerStage, nlAcks, everCommitted>>
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
                    syncJustified, usedTxn, syncPending, learnerStage, nlAcks,
                    everCommitted>>
    /\ ResetRollback

(* Snapshot captures an applied prefix and is named by lastProcessedZxid. *)
TakeSnapshot(s) ==
    /\ up[s] /\ snapshot[s] /= applied[s]
    /\ snapshot' = [snapshot EXCEPT ![s] = applied[s]]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncPending, learnerStage, nlAcks,
                    everCommitted>>
    /\ ResetRollback

(* Crash drops non-durable queues and every volatile learner/leader buffer;   *)
(* snapshot is the safe visible restart prefix.                               *)
\* FileTxnSnapLog.restore loads the newest snapshot and replays only log
\* records after it (FileTxnSnapLog.java:243-304): the recoverable history is
\* the snapshot when it extends the durable log.
RecoverableHistory(s) ==
    IF IsPrefix(durable[s], snapshot[s]) THEN snapshot[s] ELSE durable[s]

Crash(s) ==
    /\ up[s]
    /\ up' = [up EXCEPT ![s] = FALSE]
    /\ role' = [role EXCEPT ![s] = "looking"]
    /\ phase' = [phase EXCEPT ![s] = "offline"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = Nil]
    /\ durable' = [durable EXCEPT ![s] = RecoverableHistory(s)]
    /\ proposed' = [proposed EXCEPT ![s] = RecoverableHistory(s)]
    /\ queued' = [queued EXCEPT ![s] = RecoverableHistory(s)]
    /\ appended' = [appended EXCEPT ![s] = RecoverableHistory(s)]
    /\ committed' = [committed EXCEPT ![s] = snapshot[s]]
    /\ applied' = [applied EXCEPT ![s] = snapshot[s]]
    /\ recovered' = [recovered EXCEPT ![s] = <<>>]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ syncSource' = [syncSource EXCEPT ![s] = Nil]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = FALSE]
    /\ syncPending' = [syncPending EXCEPT ![s] = <<>>]
    /\ learnerStage' = [learnerStage EXCEPT ![s] = "idle"]
    /\ nlAcks' = [nlAcks EXCEPT ![s] = {}]
    /\ rollbackAuthorized' = [x \in Server |-> x = s]
    /\ UNCHANGED <<acceptedEpoch, currentEpoch, votes, leadersByEpoch,
                    snapshot, acked, commitCertified, messages,
                    usedTxn, everCommitted>>

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
                    syncPending, learnerStage, nlAcks, everCommitted>>
    /\ ResetRollback

DropMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, syncMode, syncSource, syncJustified,
                    usedTxn, syncPending, learnerStage, nlAcks, everCommitted>>
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
    \/ \E s \in Server : LearnerNewLeader(s)
    \/ \E s \in Server : LearnerAckNewLeader(s)
    \/ \E s \in Server : EnterBroadcast(s)
    \/ \E l \in Server : LeaderBroadcast(l)
    \/ \E l \in Server, t \in Txn : Propose(l, t)
    \/ \E m \in messages : ReceiveProposal(m)
    \/ \E s \in Server, t \in Txn, ep \in Epoch : ObserveCommit(s, t, ep)
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
    /\ syncPending \in [Server -> Seq(Entry)]
    /\ learnerStage \in [Server -> LearnerStages]
    /\ nlAcks \in [Server -> SUBSET Server]
    /\ everCommitted \subseteq CommitRecord

ElectionSafety == \A e \in Epoch : Cardinality(leadersByEpoch[e]) <= 1

OneActiveLeaderPerEpoch ==
    \A e \in Epoch :
        Cardinality({s \in Server : up[s] /\ role[s] = "leading"
                                    /\ acceptedEpoch[s] = e}) <= 1

CommittedHistoriesPrefix ==
    \A a, b \in Server : IsPrefix(committed[a], committed[b]) \/
                          IsPrefix(committed[b], committed[a])

ApplyRequiresCommitCertificate ==
    \A s \in Server :
        /\ IsPrefix(applied[s], committed[s])
        /\ \A k \in 1..Len(applied[s]) : commitCertified[applied[s][k].id]

PipelinePrefix ==
    \A s \in Server :
        /\ IsPrefix(durable[s], appended[s])
        /\ IsPrefix(appended[s], queued[s])
        /\ IsPrefix(queued[s], proposed[s])
        /\ IsPrefix(snapshot[s], applied[s])

EpochHistoryConsistency ==
    /\ \A s \in Server : currentEpoch[s] <= acceptedEpoch[s]
    /\ \A s \in Server : LastEpoch(durable[s]) <= acceptedEpoch[s]

SyncCompletionJustified ==
    \A s \in Server :
        (role[s] = "following" /\ phase[s] = "broadcast") =>
          /\ syncJustified[s]
          /\ leaderOf[s] \in Server
          /\ currentEpoch[s] = acceptedEpoch[s]

NoIllegalRollback ==
    \A s \in Server :
       /\ (Len(durable'[s]) >= Len(durable[s]) \/ rollbackAuthorized'[s])
       /\ (Len(committed'[s]) >= Len(committed[s]) \/ rollbackAuthorized'[s])
       /\ (Len(applied'[s]) >= Len(applied[s]) \/ rollbackAuthorized'[s])

HistoryPositionsMonotonicExceptRecovery == [][NoIllegalRollback]_allVars

Safety == TypeOK /\ ElectionSafety /\ OneActiveLeaderPerEpoch /\
          CommittedHistoriesPrefix /\ ApplyRequiresCommitCertificate /\
          PipelinePrefix /\ EpochHistoryConsistency /\ SyncCompletionJustified

\* All voting-server identities are interchangeable in the finite models.
\* TLC's permutation quotient removes only renamed copies of the same state.
ModelSymmetry == Permutations(Server)

\* Canonical TLC runs are bounded at this explicit finite execution depth.
CanonicalDepthBound == TLCGet("level") <= 23

=============================================================================
