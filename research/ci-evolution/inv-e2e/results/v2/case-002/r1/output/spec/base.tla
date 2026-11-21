------------------------------ MODULE base ------------------------------
EXTENDS Naturals, Integers, Sequences, FiniteSets, TLC

\* Reference model of the UPDATED ZooKeeper quorum implementation.
\* Source identity: artifact commit "update" (neutral two-commit history);
\* changed files Learner.java and ZooKeeperServer.java.  Line citations of the
\* form Learner.java:NNN refer to /work/new-source (the clean updated tree).
\* Update-related locations carry UPDATE-MAP comments pointing to Update.tla.

CONSTANTS Server, Txn, MaxEpoch, Nil,
          \* TRUE = updated source: NEWLEADER hands the buffered sync proposals
          \* to the log pipeline before the NEWLEADER ACK (Learner.java:749-760).
          \* FALSE is used ONLY by the attribution control under
          \* spec/evidence/old-control/ (exact-old: logged after UPTODATE).
          NewLeaderLogsPending

ASSUME /\ Server /= {}
       /\ Txn /= {}
       /\ MaxEpoch \in Nat \ {0}
       /\ Nil \notin Server
       /\ NewLeaderLogsPending \in BOOLEAN

Role == {"looking", "leading", "following"}
Phase == {"election", "discovery", "sync", "broadcast", "offline"}
SyncModes == {"NONE", "DIFF", "TRUNC", "SNAP"}
Epoch == 0..MaxEpoch
Entry == [id : Txn, epoch : Epoch]
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
          \* UPDATE-MAP (state added for the update; see Update.tla section 1)
          \* code: Learner.java:559 packetsNotCommitted; Learner.java:760 ACK;
          \*       Leader.java:1547-1585 newLeaderProposal ack set
          \* update: Update!AffectedActions, Update!NewLeaderAckDurable
          pendingSync,     \* Learner packetsNotCommitted: sync proposals not yet logged
          nlAckSent,       \* learner wrote ACK(NEWLEADER) in its current sync session
          nlAcks,          \* NEWLEADER ACKs counted by leader l (Leader.waitForNewLeaderAck)
          certEpoch,       \* ghost: epoch of the leader that first certified a txn
          \* REPAIR (trace-driven, update-focused-diff-sync event 106): the
          \* in-memory ZKDatabase history.  FLE votes and FOLLOWERINFO/ACKEPOCH
          \* report getLastLoggedZxid() = zkDb.getDataTreeLastProcessedZxid()
          \* (QuorumPeer.getLastLoggedZxid), and a new leader serves/synchronizes
          \* from it (Leader.java:593 zk.loadData uses the initialized zkDb).
          \* It can lag the durable log (see BeginElection).
          memHist

allVars == <<up, role, phase, leaderOf,
             acceptedEpoch, currentEpoch,
             votes, leadersByEpoch,
             proposed, queued, appended, durable, committed, applied,
             snapshot, recovered,
             acked, commitCertified, messages,
             syncMode, syncSource, syncJustified,
             usedTxn, rollbackAuthorized,
             pendingSync, nlAckSent, nlAcks, certEpoch, memHist>>

updVars == <<pendingSync, nlAckSent, nlAcks, certEpoch, memHist>>

IsPrefix(a, b) == Len(a) <= Len(b) /\ SubSeq(b, 1, Len(a)) = a
EntryFor(id, ep) == [id |-> id, epoch |-> ep]
TxnIds(h) == {h[k].id : k \in 1..Len(h)}
LastEpoch(h) == IF Len(h) = 0 THEN 0 ELSE h[Len(h)].epoch
LastId(h) == IF Len(h) = 0 THEN Nil ELSE h[Len(h)].id
\* Longest common prefix of two histories (prefix equality is downward closed).
CommonPrefix(a, b) ==
    LET K == {k \in 0..Len(a) : k <= Len(b) /\ SubSeq(a, 1, k) = SubSeq(b, 1, k)}
        n == CHOOSE k \in K : \A j \in K : j <= k
    IN SubSeq(a, 1, n)

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
    /\ pendingSync = [s \in Server |-> <<>>]
    /\ nlAckSent = [s \in Server |-> FALSE]
    /\ nlAcks = [s \in Server |-> {}]
    /\ certEpoch = [t \in Txn |-> 0]
    /\ memHist = [s \in Server |-> <<>>]

(* FastLeaderElection.lookForLeader: logical round and self vote.
   Leaving FOLLOWING/LEADING runs Learner/Leader.shutdown -> zk.shutdown().
   REPAIR (prior-model defect, needed by the update interaction):
   - while the server is RUNNING (public phase broadcast) the shutdown drains
     and flushes the SyncRequestProcessor (LearnerZooKeeperServer.java:155-172,
     SyncRequestProcessor.shutdown: join then flush), so queued entries become
     durable;
   - while the server is NOT running (updated code: INITIAL between NEWLEADER
     and UPTODATE, ZooKeeperServer.java:673-675) canShutdown() is false
     (ZooKeeperServer.java:784-786, LearnerZooKeeperServer.java:156-158): the
     started SyncRequestProcessor is neither stopped nor flushed and keeps
     appending/fsyncing asynchronously (AppendOne/FsyncOne stay enabled).
   The learner-local packetsNotCommitted buffer is discarded with the
   syncWithLeader frame. *)
\* UPDATE-MAP
\* code: ZooKeeperServer.java:673-675 (startupWithoutServing -> INITIAL); LearnerZooKeeperServer.java:155-172
\* update: Update!InteractionActions (MCBeginElection), Update!EnvLeakedPipeline note
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
    \* RUNNING: ZooKeeperServer.shutdown(false) shuts the processor chain down
    \* and then fast-forwards the in-memory database from the on-disk log
    \* (ZooKeeperServer.java:827-850).
    \*  - leader: its SyncRequestProcessor is inside the chain
    \*    (ProposalRequestProcessor.shutdown -> syncProcessor.shutdown,
    \*    ProposalRequestProcessor.java:94-98), so it is flushed BEFORE the
    \*    fast-forward;
    \*  - learner: its SyncRequestProcessor is shut down only AFTER
    \*    super.shutdown() returns (LearnerZooKeeperServer.java:161-169), so the
    \*    fast-forward sees only the already-durable log.
    \* Not running (updated code: INITIAL between NEWLEADER and UPTODATE):
    \* neither happens.
    /\ IF phase[s] = "broadcast"
       THEN /\ appended' = [appended EXCEPT ![s] = queued[s]]
            /\ durable' = [durable EXCEPT ![s] = queued[s]]
            /\ memHist' = [memHist EXCEPT ![s] =
                              LET ff == IF role[s] = "leading" THEN queued[s] ELSE durable[s]
                              IN IF IsPrefix(@, ff) THEN ff ELSE @]
       ELSE UNCHANGED <<appended, durable, memHist>>
    /\ pendingSync' = [pendingSync EXCEPT ![s] = <<>>]
    /\ nlAckSent' = [nlAckSent EXCEPT ![s] = FALSE]
    /\ nlAcks' = [nlAcks EXCEPT ![s] = {}]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, leadersByEpoch,
                    proposed, queued, committed, applied,
                    snapshot, recovered, acked, commitCertified, messages,
                    usedTxn, certEpoch>>
    /\ ResetRollback

(* FLE totalOrderPredicate: epoch, then last zxid/log length, then id.  The
   zxid is getLastLoggedZxid(), i.e. the in-memory database position. *)
HistoryAtLeast(candidate, voter) ==
    \/ currentEpoch[candidate] > currentEpoch[voter]
    \/ /\ currentEpoch[candidate] = currentEpoch[voter]
       /\ Len(memHist[candidate]) >= Len(memHist[voter])

CastVote(voter, candidate) ==
    /\ up[voter] /\ up[candidate]
    /\ role[voter] = "looking"
    /\ HistoryAtLeast(candidate, voter)
    /\ votes' = [votes EXCEPT ![candidate] = @ \cup {voter}]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ UNCHANGED updVars
    /\ ResetRollback

(* FLE quorum decision; Leader.lead: zk.loadData() (Leader.java:593) fixes the
   history the leader synchronizes from, then getEpochToPropose. *)
WinElection(candidate) ==
    /\ up[candidate]
    /\ role[candidate] = "looking"
    /\ Cardinality(votes[candidate]) >= Quorum
    /\ acceptedEpoch[candidate] < MaxEpoch
    /\ LET ep == acceptedEpoch[candidate] + 1 IN
       /\ leadersByEpoch[ep] = {}
       /\ role' = [role EXCEPT ![candidate] = "leading"]
       /\ phase' = [phase EXCEPT ![candidate] = "discovery"]
       /\ leaderOf' = [leaderOf EXCEPT ![candidate] = candidate]
       /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![candidate] = ep]
       /\ leadersByEpoch' = [leadersByEpoch EXCEPT ![ep] = {candidate}]
       \* Leader.java:593 zk.loadData(): an initialized in-memory database is
       \* used as is (ZooKeeperServer.loadData); it is served to learners.
       /\ recovered' = [recovered EXCEPT ![candidate] = memHist[candidate]]
    /\ nlAcks' = [nlAcks EXCEPT ![candidate] = {}]
    /\ UNCHANGED <<up, currentEpoch, votes, proposed, queued, appended,
                    durable, committed, applied, snapshot, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ UNCHANGED <<pendingSync, nlAckSent, certEpoch, memHist>>
    /\ ResetRollback

(* QuorumPeer main loop switches a LOOKING peer to FOLLOWING before discovery.
   REPAIR: FOLLOWING is entered only from LOOKING (QuorumPeer.run case LOOKING
   -> FastLeaderElection.lookForLeader -> setPeerState). *)
FollowLeader(s, l) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "looking"
    /\ role[l] = "leading"
    /\ role' = [role EXCEPT ![s] = "following"]
    /\ phase' = [phase EXCEPT ![s] = "discovery"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = l]
    /\ pendingSync' = [pendingSync EXCEPT ![s] = <<>>]
    /\ nlAckSent' = [nlAckSent EXCEPT ![s] = FALSE]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, votes, leadersByEpoch,
                    proposed, queued, appended, durable, committed, applied,
                    snapshot, recovered, acked, commitCertified, messages,
                    syncMode, syncSource, syncJustified, usedTxn>>
    /\ UNCHANGED <<nlAcks, certEpoch, memHist>>
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
                    syncJustified, usedTxn>>
    /\ UNCHANGED updVars
    /\ ResetRollback

(* Leader.waitForEpochAck completes after a participant quorum; the leader
   persists currentEpoch, publishes SYNCHRONIZATION (Leader.java:660) and counts
   its own NEWLEADER ACK (Leader.java:663 waitForNewLeaderAck(self.getId())). *)
\* UPDATE-MAP
\* code: Leader.java:660-663
\* update: Update!InteractionActions (MCFinishDiscovery)
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
                    syncJustified, usedTxn>>
    /\ UNCHANGED <<pendingSync, nlAckSent, certEpoch, memHist>>
    /\ ResetRollback

\* The leader synchronizes learners from its loaded history recovered[l] and
\* decides from the learner's REPORTED position (ACKEPOCH lastLoggedZxid, i.e.
\* memHist), not from the learner's disk (LearnerHandler.syncFollower).
DiffAllowed(s, l) == IsPrefix(memHist[s], recovered[l])
TruncAllowed(s, l) == IsPrefix(recovered[l], memHist[s])

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
                    usedTxn>>
    /\ UNCHANGED updVars
    /\ ResetRollback

(* LearnerHandler.syncFollower chooses DIFF/TRUNC/SNAP under the DB log lock. *)
SelectSync(s, l, mode) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "following" /\ leaderOf[s] = l
    /\ phase[s] = "sync" /\ phase[l] = "sync"
    /\ syncSource[s] = l
    /\ ~syncJustified[s]
    /\ mode \in SyncModes \ {"NONE"}
    /\ IF mode = "DIFF" THEN DiffAllowed(s, l)
       ELSE IF mode = "TRUNC" THEN TruncAllowed(s, l)
       ELSE ~(DiffAllowed(s, l) \/ TruncAllowed(s, l)) \/ memHist[s] = <<>>
    /\ syncMode' = [syncMode EXCEPT ![s] = mode]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncSource, syncJustified,
                    usedTxn>>
    /\ UNCHANGED updVars
    /\ ResetRollback

(* Learner.syncWithLeader consumes the sync directive and the proposal stream
   queued before NEWLEADER (replaces the prior atomic CompleteSync, which made
   the leader history durable at the learner immediately).
   - DIFF (Learner.java:562-565, 614, 621-641): snapshotNeeded=false and
     writeToTxnLog=true, so every streamed PROPOSAL is buffered in
     packetsNotCommitted and its COMMIT in packetsCommitted; nothing is logged.
   - TRUNC (Learner.java:586-597): the on-disk log is truncated to the leader's
     zxid and the database reloaded; the stream suffix is empty.
   - SNAP (Learner.java:566-584, 738-741): the data tree is replaced by the
     leader snapshot; NEWLEADER persists it with takeSnapshot(syncSnapshot)
     before the ACK.  The snapshot persistence is folded into this step (both
     precede the NEWLEADER ACK, which is the update boundary).
   recovered[s] records the leader history H received in this session.
   Abstraction: the model synchronizes only while the leader is in its
   SYNCHRONIZATION phase (prior scope); the learner pipeline must be drained
   (queued = durable), i.e. a leaked pipeline from an aborted session has
   flushed before the next session (see Update.tla CR-2 note). *)
\* UPDATE-MAP
\* code: Learner.java:559-641 (buffering into packetsNotCommitted)
\* update: Update!AffectedActions (MCReceiveSyncPayload)
ReceiveSyncPayload(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncSource[s] \in Server
    /\ syncMode[s] \in SyncModes \ {"NONE"}
    /\ ~syncJustified[s]
    /\ queued[s] = durable[s]
    /\ LET l == syncSource[s] IN
       LET H == recovered[l] IN
       /\ up[l] /\ role[l] = "leading" /\ phase[l] = "sync"
       \* The selected sync and NEWLEADER exchange are bound to one epoch.
       /\ acceptedEpoch[s] = acceptedEpoch[l]
       /\ CASE syncMode[s] = "DIFF" ->
                 /\ DiffAllowed(s, l)
                 \* the stream starts after the REPORTED position; it is
                 \* logged after whatever the learner's disk already holds
                 /\ pendingSync' = [pendingSync EXCEPT ![s] =
                                      SubSeq(H, Len(memHist[s]) + 1, Len(H))]
                 /\ UNCHANGED <<proposed, queued, appended, durable, memHist>>
            [] syncMode[s] = "TRUNC" ->
                 /\ TruncAllowed(s, l)
                 \* ZKDatabase.truncateLog: truncate on disk, clear and reload
                 /\ memHist' = [memHist EXCEPT ![s] = H]
                 /\ durable' = [durable EXCEPT ![s] = H]
                 /\ appended' = [appended EXCEPT ![s] = H]
                 /\ queued' = [queued EXCEPT ![s] = H]
                 /\ proposed' = [proposed EXCEPT ![s] = H]
                 /\ pendingSync' = [pendingSync EXCEPT ![s] = <<>>]
            [] OTHER ->
                 \* ZKDatabase.deserializeSnapshot replaces the data tree
                 /\ memHist' = [memHist EXCEPT ![s] = H]
                 /\ durable' = [durable EXCEPT ![s] = H]
                 /\ appended' = [appended EXCEPT ![s] = H]
                 /\ queued' = [queued EXCEPT ![s] = H]
                 /\ proposed' = [proposed EXCEPT ![s] = H]
                 /\ pendingSync' = [pendingSync EXCEPT ![s] = <<>>]
       \* Replacing/truncating history keeps only the prefix shared with H.
       /\ committed' = [committed EXCEPT ![s] = CommonPrefix(committed[s], H)]
       /\ applied' = [applied EXCEPT ![s] = CommonPrefix(applied[s], H)]
       /\ snapshot' = [snapshot EXCEPT ![s] = CommonPrefix(snapshot[s], H)]
       /\ recovered' = [recovered EXCEPT ![s] = H]
       /\ syncJustified' = [syncJustified EXCEPT ![s] = TRUE]
       /\ rollbackAuthorized' = [x \in Server |-> x = s]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, acked, commitCertified, messages,
                    syncMode, syncSource, usedTxn>>
    /\ UNCHANGED <<nlAckSent, nlAcks, certEpoch>>

(* NEWLEADER: self.setCurrentEpoch(newEpoch) (Learner.java:743) persists the
   epoch file before the learner acknowledges. *)
PersistCurrentEpoch(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncJustified[s] /\ leaderOf[s] \in Server
    /\ ~nlAckSent[s]
    /\ acceptedEpoch[s] = acceptedEpoch[leaderOf[s]]
    /\ currentEpoch[s] /= acceptedEpoch[s]
    /\ currentEpoch' = [currentEpoch EXCEPT ![s] = acceptedEpoch[s]]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ UNCHANGED updVars
    /\ ResetRollback

(* UPDATED: the NEWLEADER handler now clears the reported sync mode right after
   setCurrentEpoch and before the ACK (Learner.java:749-750); the exact-old
   code did this only after UPTODATE.  *)
\* UPDATE-MAP
\* code: Learner.java:749-750 (moved from the post-UPTODATE block)
\* update: Update!AffectedActions (MCClearSyncMode)
ClearSyncMode(s) ==
    /\ up[s] /\ phase[s] = "sync" /\ syncMode[s] /= "NONE"
    /\ syncJustified[s] /\ ~nlAckSent[s]
    /\ currentEpoch[s] = acceptedEpoch[s]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncSource, syncJustified,
                    usedTxn>>
    /\ UNCHANGED updVars
    /\ ResetRollback

(* UPDATED NEWLEADER completion (Learner.java:749-760):
     zk.startupWithoutServing()  -- request processors incl. SyncRequestProcessor
                                    start; server state INITIAL (ZooKeeperServer.java:673-698)
     for p in packetsNotCommitted: fzk.logRequest(p)  -- pendingTxns.add +
                                    syncProcessor.processRequest (enqueue only,
                                    FollowerZooKeeperServer.java:81-88)
     packetsNotCommitted.clear()
     writePacket(ACK(newLeaderZxid), true)
   logRequest only ENQUEUES to the asynchronous SyncRequestProcessor; append and
   fsync happen later in AppendOne/FsyncOne.  The ACK is consumed by the
   leader's LearnerHandler -> Leader.waitForNewLeaderAck (Leader.java:1547-1585),
   which counts it while the leader is still waiting for the NEWLEADER quorum.
   Sending and counting are merged (a lost/late ACK only weakens the leader's
   quorum, never the follower's obligations).
   With NewLeaderLogsPending = FALSE (attribution control only) the buffer is
   left for UPTODATE, as in the exact-old source. *)
\* UPDATE-MAP
\* code: Learner.java:749-760; ZooKeeperServer.java:673-698; FollowerZooKeeperServer.java:81-88
\* update: Update!AffectedActions (MCAckNewLeader), Update!NewLeaderAckDurable
AckNewLeader(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncJustified[s] /\ ~nlAckSent[s]
    /\ leaderOf[s] \in Server
    /\ currentEpoch[s] = acceptedEpoch[s]
    /\ syncMode[s] = "NONE"
    /\ IF NewLeaderLogsPending
       THEN /\ proposed' = [proposed EXCEPT ![s] = @ \o pendingSync[s]]
            /\ queued' = [queued EXCEPT ![s] = @ \o pendingSync[s]]
            /\ pendingSync' = [pendingSync EXCEPT ![s] = <<>>]
       ELSE UNCHANGED <<proposed, queued, pendingSync>>
    /\ nlAckSent' = [nlAckSent EXCEPT ![s] = TRUE]
    /\ LET l == leaderOf[s] IN
       nlAcks' = IF /\ up[l] /\ role[l] = "leading" /\ phase[l] = "sync"
                    /\ acceptedEpoch[l] = acceptedEpoch[s]
                 THEN [nlAcks EXCEPT ![l] = @ \cup {s}]
                 ELSE nlAcks
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, appended, durable, committed,
                    applied, snapshot, recovered, acked, commitCertified,
                    messages, syncMode, syncSource, syncJustified, usedTxn>>
    /\ UNCHANGED <<certEpoch, memHist>>
    /\ ResetRollback

(* UPDATED UPTODATE path (Learner.java:711-725, 765-785): ACK(UPTODATE),
   zk.startServing() (RUNNING), then log any buffered proposals and deliver the
   buffered commits (fzk.commit).  UPTODATE is queued by the LearnerHandler only
   after learnerMaster.waitForStartup() (LearnerHandler.java:641-648), i.e. after
   the leader has activated.  The streamed history H (recovered[s]) was
   committed by the NEWLEADER quorum, so it becomes this learner's committed
   prefix. *)
\* UPDATE-MAP
\* code: Learner.java:711-725, 765-785
\* update: Update!AffectedActions (MCEnterBroadcast)
EnterBroadcast(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncJustified[s] /\ nlAckSent[s]
    /\ currentEpoch[s] = acceptedEpoch[s]
    /\ syncMode[s] = "NONE"
    /\ leaderOf[s] \in Server
    /\ LET l == leaderOf[s] IN
       /\ role[l] = "leading" /\ phase[l] = "broadcast"
       /\ acceptedEpoch[l] = acceptedEpoch[s]
    /\ phase' = [phase EXCEPT ![s] = "broadcast"]
    /\ proposed' = [proposed EXCEPT ![s] = @ \o pendingSync[s]]
    /\ queued' = [queued EXCEPT ![s] = @ \o pendingSync[s]]
    /\ pendingSync' = [pendingSync EXCEPT ![s] = <<>>]
    /\ committed' = [committed EXCEPT ![s] = recovered[s]]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, appended, durable, applied, snapshot,
                    recovered, acked, commitCertified, messages, syncMode,
                    syncSource, syncJustified, usedTxn>>
    /\ UNCHANGED <<nlAckSent, nlAcks, certEpoch, memHist>>
    /\ ResetRollback

(* Leader.lead: after waitForNewLeaderAck forms a quorum of NEWLEADER ACKs
   (Leader.java:663, 1547-1585) the leader starts its server (startZkServer,
   Leader.java:688) and serves its loaded history, i.e. the NEWLEADER quorum
   commits H = recovered[l] (zookeeperInternals.md:196-197).
   REPAIR: the prior model gated activation on followers having reached their
   public BROADCAST phase (after UPTODATE) and never committed the leader's
   loaded history; the implementation counts NEWLEADER ACKs instead. *)
\* UPDATE-MAP
\* code: Leader.java:660-712, 1547-1585
\* update: Update!InteractionActions (MCLeaderBroadcast), Update!CommittedDurableOnQuorum
LeaderBroadcast(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "sync"
    /\ Cardinality(nlAcks[l]) >= Quorum
    /\ IsPrefix(committed[l], recovered[l])
    /\ phase' = [phase EXCEPT ![l] = "broadcast"]
    /\ committed' = [committed EXCEPT ![l] = recovered[l]]
    /\ commitCertified' = [t \in Txn |-> commitCertified[t] \/ t \in TxnIds(recovered[l])]
    /\ certEpoch' = [t \in Txn |->
                       IF certEpoch[t] = 0 /\ t \in TxnIds(recovered[l])
                       THEN acceptedEpoch[l] ELSE certEpoch[t]]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, applied, snapshot, recovered, acked,
                    messages, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ UNCHANGED <<pendingSync, nlAckSent, nlAcks, memHist>>
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
                    syncMode, syncSource, syncJustified>>
    /\ UNCHANGED updVars
    /\ ResetRollback

ReceiveProposal(m) ==
    /\ m \in messages /\ m.kind = "proposal"
    /\ up[m.to] /\ role[m.to] = "following" /\ phase[m.to] = "broadcast"
    /\ leaderOf[m.to] = m.from
    \* A learner's packet stream reaches broadcast only for its synchronized
    \* current epoch; a stale connection cannot enqueue a later-epoch proposal.
    /\ currentEpoch[m.to] = m.epoch
    /\ LET ent == EntryFor(m.id, m.epoch) IN
       /\ proposed' = [proposed EXCEPT ![m.to] = Append(@, ent)]
       /\ queued' = [queued EXCEPT ![m.to] = Append(@, ent)]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, appended, durable, committed,
                    applied, snapshot, recovered, acked, commitCertified,
                    syncMode, syncSource, syncJustified, usedTxn>>
    /\ UNCHANGED updVars
    /\ ResetRollback

\* REPAIR: the prior QueueLearnerProposal (a learner inventing a fresh txn id
\* during sync) and ObserveCommit (a learner certifying a commit without any
\* leader quorum) were removed.  Learner.syncWithLeader only buffers PROPOSAL
\* and COMMIT packets streamed by the leader (Learner.java:621-667); that
\* buffering is ReceiveSyncPayload/AckNewLeader/EnterBroadcast above.

(* SyncRequestProcessor append writes the txn stream but has not fsynced it. *)
AppendOne(s) ==
    /\ up[s] /\ Len(appended[s]) < Len(queued[s])
    /\ LET ent == queued[s][Len(appended[s]) + 1] IN
       appended' = [appended EXCEPT ![s] = Append(@, ent)]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ UNCHANGED updVars
    /\ ResetRollback

(* FileTxnLog.commit forces an appended entry; ACK is only created afterward
   (SyncRequestProcessor.flush -> SendAckRequestProcessor).  The ACK goes over
   the learner's current leader connection, if any. *)
FsyncOne(s) ==
    /\ up[s] /\ Len(durable[s]) < Len(appended[s])
    /\ LET ent == appended[s][Len(durable[s]) + 1] IN
       /\ durable' = [durable EXCEPT ![s] = Append(@, ent)]
       /\ IF role[s] = "leading"
          THEN /\ acked' = [acked EXCEPT ![ent.id] = @ \cup {s}]
               /\ messages' = messages
          ELSE /\ acked' = acked
               /\ messages' =
                    IF leaderOf[s] \in Server
                    THEN messages \cup
                           {[kind |-> "ack", from |-> s, to |-> leaderOf[s],
                             id |-> ent.id, epoch |-> ent.epoch]}
                    ELSE messages
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    committed, applied, snapshot, recovered,
                    commitCertified, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ UNCHANGED updVars
    /\ ResetRollback

DeliverAck(m) ==
    /\ m \in messages /\ m.kind = "ack" /\ up[m.to]
    /\ acked' = [acked EXCEPT ![m.id] = @ \cup {m.from}]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered,
                    commitCertified, syncMode, syncSource, syncJustified,
                    usedTxn>>
    /\ UNCHANGED updVars
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
       /\ certEpoch' = [certEpoch EXCEPT ![t] =
                          IF @ = 0 THEN acceptedEpoch[l] ELSE @]
       /\ messages' = messages \cup
            {[kind |-> "commit", from |-> l, to |-> s,
              id |-> t, epoch |-> ent.epoch] : s \in Server \ {l}}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, applied, snapshot, recovered, acked, syncMode,
                    syncSource, syncJustified, usedTxn>>
    /\ UNCHANGED <<pendingSync, nlAckSent, nlAcks, memHist>>
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
                    syncSource, syncJustified, usedTxn>>
    /\ UNCHANGED updVars
    /\ ResetRollback

(* FinalRequestProcessor applies only a certified, in-order commit. *)
ApplyOne(s) ==
    /\ up[s] /\ Len(applied[s]) < Len(committed[s])
    /\ LET ent == committed[s][Len(applied[s]) + 1] IN
       /\ commitCertified[ent.id]
       /\ applied' = [applied EXCEPT ![s] = Append(@, ent)]
       \* the data tree advances to the applied position
       /\ memHist' = [memHist EXCEPT ![s] =
                         IF Len(applied'[s]) > Len(@) THEN applied'[s] ELSE @]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ UNCHANGED <<pendingSync, nlAckSent, nlAcks, certEpoch>>
    /\ ResetRollback

(* Snapshot captures an applied prefix and is named by lastProcessedZxid. *)
TakeSnapshot(s) ==
    /\ up[s] /\ snapshot[s] /= applied[s]
    /\ snapshot' = [snapshot EXCEPT ![s] = applied[s]]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ UNCHANGED updVars
    /\ ResetRollback

(* Crash drops non-durable queues and the learner sync buffers; snapshot is the
   safe visible restart prefix. *)
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
    /\ rollbackAuthorized' = [x \in Server |-> x = s]
    /\ pendingSync' = [pendingSync EXCEPT ![s] = <<>>]
    /\ nlAckSent' = [nlAckSent EXCEPT ![s] = FALSE]
    /\ nlAcks' = [nlAcks EXCEPT ![s] = {}]
    /\ memHist' = [memHist EXCEPT ![s] = <<>>]
    /\ UNCHANGED <<acceptedEpoch, currentEpoch, votes, leadersByEpoch,
                    durable, snapshot, acked, commitCertified, messages,
                    usedTxn, certEpoch>>

(* restore() loads snapshot then replays durable log into tentative recovery state. *)
Restart(s) ==
    /\ ~up[s]
    /\ up' = [up EXCEPT ![s] = TRUE]
    /\ phase' = [phase EXCEPT ![s] = "election"]
    /\ recovered' = [recovered EXCEPT ![s] = durable[s]]
    \* loadDataBase replays snapshot + durable log into memory
    /\ memHist' = [memHist EXCEPT ![s] = durable[s]]
    /\ UNCHANGED <<role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, acked, commitCertified,
                    messages, syncMode, syncSource, syncJustified, usedTxn>>
    /\ UNCHANGED <<pendingSync, nlAckSent, nlAcks, certEpoch>>
    /\ ResetRollback

DropMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, syncMode, syncSource, syncJustified,
                    usedTxn>>
    /\ UNCHANGED updVars
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
    \/ \E s \in Server : ReceiveSyncPayload(s)
    \/ \E s \in Server : PersistCurrentEpoch(s)
    \/ \E s \in Server : ClearSyncMode(s)
    \/ \E s \in Server : AckNewLeader(s)
    \/ \E s \in Server : EnterBroadcast(s)
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
\* verified: update
\* review:   extended with the four update variables.
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
    /\ pendingSync \in [Server -> Seq(Entry)]
    /\ nlAckSent \in [Server -> BOOLEAN]
    /\ nlAcks \in [Server -> SUBSET Server]
    /\ certEpoch \in [Txn -> Epoch]
    /\ memHist \in [Server -> Seq(Entry)]

\* REQ-EVIDENCE ElectionSafety
\* intent:   At most one server ever takes leadership of any given epoch.
\* status:   requirement
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:130 "Leadership activation will ensure that only one leader uses a given epoch" -> at most one leader per epoch
\* watch:    Leader.java:getEpochToPropose; Leader.java:waitForEpochAck; Learner.java:registerWithLeader; FastLeaderElection.java:lookForLeader
\* verified: update (watch not touched by the update; unchanged)
ElectionSafety == \A e \in Epoch : Cardinality(leadersByEpoch[e]) <= 1

\* REQ-EVIDENCE OneActiveLeaderPerEpoch
\* intent:   At any moment, at most one running server is leading in any given epoch.
\* status:   requirement
\* evidence: doc zookeeperInternals.md:130 "Leadership activation will ensure that only one leader uses a given epoch"
\* watch:    Leader.java:lead; Leader.java:getEpochToPropose; QuorumPeer.java:run; Learner.java:registerWithLeader
\* verified: update (watch not touched; unchanged)
OneActiveLeaderPerEpoch ==
    \A e \in Epoch :
        Cardinality({s \in Server : up[s] /\ role[s] = "leading"
                                    /\ acceptedEpoch[s] = e}) <= 1

\* REQ-EVIDENCE CommittedHistoriesPrefix
\* intent:   For any two servers, one server's sequence of committed transactions is a prefix of the other's.
\* status:   requirement
\* evidence: doc zookeeperInternals.md:63 "message `a` will be delivered before `b` by all"
\* evidence: doc zookeeperInternals.md:59 "message `m` will be eventually delivered by all servers."
\* watch:    Leader.java:tryToCommit; Learner.java:syncWithLeader; LearnerHandler.java:syncFollower; FollowerZooKeeperServer.java:commit
\* verified: update (watch Learner.java:syncWithLeader touched; kept, see spec/invariant-evidence.json)
CommittedHistoriesPrefix ==
    \A a, b \in Server : IsPrefix(committed[a], committed[b]) \/
                          IsPrefix(committed[b], committed[a])

\* REQ-EVIDENCE ApplyRequiresCommitCertificate
\* intent:   A server applies only transactions that a quorum has committed, and applies them in its commit order.
\* status:   requirement
\* evidence: comment Leader.java:902 "in order to be committed, a proposal must be accepted by a quorum."
\* evidence: doc zookeeperInternals.md:117 "committed when a quorum of them acknowledge the proposal."
\* watch:    CommitProcessor.java:run; Leader.java:tryToCommit; FollowerZooKeeperServer.java:commit; Learner.java:syncWithLeader
\* verified: update (watch Learner.java:syncWithLeader touched; kept, see spec/invariant-evidence.json)
ApplyRequiresCommitCertificate ==
    \A s \in Server :
        /\ IsPrefix(applied[s], committed[s])
        /\ \A k \in 1..Len(applied[s]) : commitCertified[applied[s][k].id]

\* REQ-EVIDENCE PipelinePrefix
\* intent:   On every server the fsynced, written and queued sequences are successive prefixes of the proposal sequence, and the snapshot is a prefix of the applied sequence.
\* status:   mixed
\* clause durableInProposalOrder: requirement — zookeeperInternals.md:229, :245, :226.
\* clause intermediateStages: impl-abstraction — SyncRequestProcessor queue/append/flush stages.
\* clause snapshotWithinApplied: requirement — zookeeperAdmin.md:2588-2594.
\* watch:    SyncRequestProcessor.java:run; FollowerZooKeeperServer.java:logRequest; ZooKeeperServer.java:takeSnapshot
\* verified: update (FollowerZooKeeperServer.logRequest is now also called at NEWLEADER; kept with keep-evidence)
PipelinePrefix ==
    \A s \in Server :
        /\ IsPrefix(durable[s], appended[s])
        /\ IsPrefix(appended[s], queued[s])
        /\ IsPrefix(queued[s], proposed[s])
        /\ IsPrefix(snapshot[s], applied[s])

\* REQ-EVIDENCE EpochHistoryConsistency
\* intent:   On every server the current epoch never exceeds the accepted epoch, and the last fsynced log entry carries no epoch later than the accepted epoch.
\* status:   mixed
\* clause currentEpochAtMostAccepted: requirement — history 19d85670 message; Zab1_0Test:614-615, 748-749.
\* clause logEpochAtMostAccepted: unknown — only impl (QuorumPeer.java:1122).
\* watch:    QuorumPeer.java:setCurrentEpoch; Learner.java:syncWithLeader; Leader.java:lead
\* verified: update (Learner.java:syncWithLeader touched; setCurrentEpoch ordering unchanged; kept)
EpochHistoryConsistency ==
    /\ \A s \in Server : currentEpoch[s] <= acceptedEpoch[s]
    /\ \A s \in Server : LastEpoch(durable[s]) <= acceptedEpoch[s]

\* REQ-EVIDENCE SyncCompletionJustified
\* intent:   A follower in the broadcast phase has completed synchronization with its leader, has an identified leader, and has set its current epoch equal to its accepted epoch.
\* status:   mixed
\* evidence: doc zookeeperInternals.md:194 "A follower will ACK the NEW_LEADER proposal after it has synced with the leader."
\* clause syncedBeforeBroadcast: requirement — zookeeperInternals.md:194; QuorumPeerMainTest:1179.
\* clause epochsAlignedInBroadcast: requirement — Zab1_0Test:636-637 and 779-780.
\* clause leaderKnown: model-internal.
\* watch:    Follower.java:followLeader; Learner.java:syncWithLeader; Leader.java:waitForNewLeaderAck
\* verified: update (watch touched; strengthened to also require the NEWLEADER ACK, see spec/invariant-evidence.json)
SyncCompletionJustified ==
    \A s \in Server :
        (role[s] = "following" /\ phase[s] = "broadcast") =>
          /\ syncJustified[s]
          /\ nlAckSent[s]
          /\ leaderOf[s] \in Server
          /\ currentEpoch[s] = acceptedEpoch[s]

\* REQ-EVIDENCE NoIllegalRollback
\* intent:   A server's durable log, committed prefix and applied prefix never shrink, except when the server crashes or installs its leader's history during synchronization.
\* status:   mixed
\* clause durableNoRollback: requirement — zookeeperInternals.md:119 and 182-183, TxnLog.java:83.
\* clause appliedNoRollback: requirement — zookeeperOver.md:166-171, zookeeperProgrammers.md:1176-1178.
\* clause committedNoRollback: unknown — only impl.
\* watch:    Learner.java:syncWithLeader; ZKDatabase.java:truncateLog; ZKDatabase.java:deserializeSnapshot
\* verified: update (watch touched; rollback authorization moved to ReceiveSyncPayload; kept)
NoIllegalRollback ==
    \A s \in Server :
       /\ (Len(durable'[s]) >= Len(durable[s]) \/ rollbackAuthorized'[s])
       /\ (Len(committed'[s]) >= Len(committed[s]) \/ rollbackAuthorized'[s])
       /\ (Len(applied'[s]) >= Len(applied[s]) \/ rollbackAuthorized'[s])

\* REQ-EVIDENCE HistoryPositionsMonotonicExceptRecovery -> alias of [][NoIllegalRollback]_allVars; see REQ-EVIDENCE NoIllegalRollback
HistoryPositionsMonotonicExceptRecovery == [][NoIllegalRollback]_allVars

Safety == TypeOK /\ ElectionSafety /\ OneActiveLeaderPerEpoch /\
          CommittedHistoriesPrefix /\ ApplyRequiresCommitCertificate /\
          PipelinePrefix /\ EpochHistoryConsistency /\ SyncCompletionJustified

\* All voting-server identities are interchangeable in the finite models.
ModelSymmetry == Permutations(Server)

\* Planned exploration budget: states found after ~29 minutes are not expanded,
\* so TLC terminates normally with statistics.  A run that hits this budget is
\* LIMITED_COVERAGE, never an exhaustive pass.
TimeBudget == TLCGet("duration") <= 1740

\* Canonical TLC runs are exhaustive through this explicit finite execution depth.
CanonicalDepthBound == TLCGet("level") <= 23

=============================================================================
