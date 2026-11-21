------------------------------ MODULE base ------------------------------
(***************************************************************************)
(* Specula reference model of ZooKeeper Zab (participants only) for the    *)
(* UPDATED source revision (artifact commit "update", 2efbdfc).            *)
(*                                                                         *)
(* Relative to the V0 prior, learner synchronisation is no longer one      *)
(* atomic CompleteSync step.  The leader->learner packet stream            *)
(* (LearnerHandler queuedPackets over TCP) is the FIFO `lq`, and the       *)
(* learner's Learner.syncWithLeader buffers (packetsNotCommitted,          *)
(* packetsCommitted, writeToTxnLog) are explicit.  The update moved the    *)
(* logging of packetsNotCommitted, setSyncMode(NONE) and server startup     *)
(* (now startupWithoutServing -> State.INITIAL) in front of the NEWLEADER  *)
(* ACK and clears packetsNotCommitted there; see the UPDATE-MAP comments.  *)
(*                                                                         *)
(* Source paths are relative to zookeeper-server/src/main/java/org/apache/ *)
(* zookeeper/server/ in the updated tree.                                  *)
(***************************************************************************)
EXTENDS Naturals, Integers, Sequences, FiniteSets, TLC

CONSTANTS Server, Txn, MaxEpoch, Nil

ASSUME /\ Server /= {}
       /\ Txn /= {}
       /\ MaxEpoch \in Nat \ {0}
       /\ Nil \notin Server
       /\ Nil \notin Txn

Role == {"looking", "leading", "following"}
Phase == {"election", "discovery", "sync", "broadcast", "offline"}
SyncModes == {"NONE", "DIFF", "TRUNC", "SNAP"}
Epoch == 0..MaxEpoch
Entry == [id : Txn, epoch : Epoch]
MsgKind == {"proposal", "ack", "commit"}
Message == [kind : MsgKind, from : Server, to : Server, id : Txn, epoch : Epoch]
\* Learner -> leader ACK of NEWLEADER (Learner.java:760); carries only the epoch.
NlAckMessage == [kind : {"nlack"}, from : Server, to : Server, id : {Nil}, epoch : Epoch]
Marker(ep) == [id |-> Nil, epoch |-> ep]
SyncPacket == [type : {"PROPOSAL", "COMMIT"}, ent : Entry]
              \cup [type : {"NEWLEADER", "UPTODATE"}, ent : [id : {Nil}, epoch : Epoch]]
\* Progress of Learner.syncWithLeader (learner thread):
\*  none      - not inside syncWithLeader's packet loop
\*  loop      - after the DIFF/TRUNC/SNAP directive, reading packets
\*  nlEpoch   - NEWLEADER consumed, snapshot (if needed) + currentEpoch persisted
\*  nlStarted - setSyncMode(NONE) + zk.startupWithoutServing() done (update)
\*  nlAcked   - packetsNotCommitted logged/cleared and NEWLEADER ACKed (update)
\*  serving   - UPTODATE consumed and zk.startServing() done; post-loop work
\*  failed    - an exception escaped syncWithLeader (e.g. NullPointerException)
SyncStages == {"none", "loop", "nlEpoch", "nlStarted", "nlAcked", "serving", "failed"}
\* Leader-side LearnerHandler progress for a learner:
\*  fwd (startForwarding done, NEWLEADER not yet queued), nl, utd.
HandlerStages == {"none", "fwd", "nl", "utd"}
\* ZooKeeperServer.State of the learner/leader server object (update adds INITIAL
\* with request processors already running).
ZkStates == {"none", "initial", "running"}
SyncErrorKinds == {"NPE", "UNMATCHED_COMMIT"}

Quorum == (Cardinality(Server) \div 2) + 1

VARIABLES up, role, phase, leaderOf,
          acceptedEpoch, currentEpoch,
          votes, leadersByEpoch,
          proposed, queued, appended, durable, committed, applied,
          snapshot, recovered,
          acked, commitCertified, messages,
          syncMode, syncSource, syncJustified,
          usedTxn, rollbackAuthorized,
          lq, pnc, pcm, toLog, syncStage, hstage, nlAcked, zkState,
          syncTarget, epochTarget, syncError

electionVars == <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                  votes, leadersByEpoch>>
histVars == <<proposed, queued, appended, durable, committed, applied,
              snapshot, recovered>>
commitVars == <<acked, commitCertified, messages>>
syncVars == <<syncMode, syncSource, syncJustified, lq, pnc, pcm, toLog,
              syncStage, hstage, nlAcked, zkState>>
ghostVars == <<usedTxn, rollbackAuthorized, syncTarget, epochTarget, syncError>>
allVars == <<electionVars, histVars, commitVars, syncVars, ghostVars>>

IsPrefix(a, b) == Len(a) <= Len(b) /\ SubSeq(b, 1, Len(a)) = a
EntryFor(id, ep) == [id |-> id, epoch |-> ep]
TxnIds(h) == {h[k].id : k \in 1..Len(h)}
LastEpoch(h) == IF Len(h) = 0 THEN 0 ELSE h[Len(h)].epoch
LastId(h) == IF Len(h) = 0 THEN Nil ELSE h[Len(h)].id
Contains(h, e) == \E k \in 1..Len(h) : h[k] = e
\* SyncRequestProcessor appends every logged request; an already-logged entry
\* re-sent by a later session is the same zxid, so the history is idempotent.
LogAppend(h, e) == IF Contains(h, e) THEN h ELSE Append(h, e)
After(h, n) == IF n >= Len(h) THEN <<>> ELSE SubSeq(h, n + 1, Len(h))
\* zxid order: epoch of the last entry, then count of entries in that epoch.
CountInLastEpoch(h) == Cardinality({k \in 1..Len(h) : h[k].epoch = LastEpoch(h)})
ZxidGeq(a, b) == \/ LastEpoch(a) > LastEpoch(b)
                 \/ /\ LastEpoch(a) = LastEpoch(b)
                    /\ CountInLastEpoch(a) >= CountInLastEpoch(b)
PropPkt(e) == [type |-> "PROPOSAL", ent |-> e]
CommitPkt(e) == [type |-> "COMMIT", ent |-> e]
PropCommitPairs(h) ==
    [k \in 1..(2 * Len(h)) |->
        IF k % 2 = 1 THEN PropPkt(h[(k + 1) \div 2]) ELSE CommitPkt(h[k \div 2])]
Props(h) == [k \in 1..Len(h) |-> PropPkt(h[k])]

CertifiedPrefix(h) ==
    LET ks == {k \in 0..Len(h) : \A j \in 1..k : commitCertified[h[j].id]}
    IN SubSeq(h, 1, CHOOSE k \in ks : \A j \in ks : j <= k)

ResetRollback == rollbackAuthorized' = [s \in Server |-> FALSE]
AuthorizeRollback(s) == rollbackAuthorized' = [x \in Server |-> x = s]

\* An established leader has started its ZooKeeperServer (Leader.startZkServer).
Established(l) == up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
\* Position reported by QuorumPeer.getLastLoggedZxid(): the in-memory data tree
\* (QuorumPeer.java:1257-1262), i.e. applied state while the server is
\* RUNNING and the loaded/fast-forwarded tree (`recovered`) otherwise.
DbPos(s) == IF zkState[s] = "running" THEN applied[s] ELSE recovered[s]
\* LearnerHandler.syncFollower syncs from the committed log (established
\* leader) or from the database loaded by Leader.lead -> zk.loadData().
LeaderHist(l) == IF Established(l) THEN committed[l] ELSE recovered[l]
LeaderTree(l) == IF Established(l) THEN applied[l] ELSE recovered[l]
\* Leader.startForwarding: outstanding (proposed, uncommitted) proposals.
Outstanding(l) == IF Established(l) THEN After(proposed[l], Len(committed[l])) ELSE <<>>

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
    /\ lq = [s \in Server |-> <<>>]
    /\ pnc = [s \in Server |-> <<>>]
    /\ pcm = [s \in Server |-> <<>>]
    /\ toLog = [s \in Server |-> FALSE]
    /\ syncStage = [s \in Server |-> "none"]
    /\ hstage = [s \in Server |-> "none"]
    /\ nlAcked = [s \in Server |-> {}]
    /\ zkState = [s \in Server |-> "none"]
    /\ syncTarget = [s \in Server |-> <<>>]
    /\ epochTarget = [s \in Server |-> <<>>]
    /\ syncError = {}

(***************************************************************************)
(* Role exit.  QuorumPeer.run's finally block calls follower/leader        *)
(* shutdown -> Learner.shutdown (Learner.java:850-866) -> zk.shutdown().   *)
(* LearnerZooKeeperServer.shutdown (LearnerZooKeeperServer.java:155-174)   *)
(* and ZooKeeperServer.shutdown (ZooKeeperServer.java:803-855) return      *)
(* immediately unless canShutdown() (state RUNNING/ERROR).  From RUNNING,  *)
(* SyncRequestProcessor.shutdown drains and flushes and                    *)
(* zkDb.fastForwardDataBase() replays the log into the tree.  From the     *)
(* update's INITIAL state nothing is shut down: the request processors     *)
(* keep running (AppendOne/FsyncOne stay enabled) and the tree is not      *)
(* fast-forwarded.                                                         *)
(* UPDATE-MAP                                                              *)
(* code: ZooKeeperServer.java:669-704 (startupWithoutServing/State.INITIAL)*)
(* update: Update!AffectedActions (MCBeginElection, MCLearnerAbort)        *)
(***************************************************************************)
ExitHist(s) ==
    IF zkState[s] = "running"
    THEN /\ appended' = [appended EXCEPT ![s] = queued[s]]
         /\ durable' = [durable EXCEPT ![s] = queued[s]]
         /\ recovered' = [recovered EXCEPT ![s] = queued[s]]
    ELSE UNCHANGED <<appended, durable, recovered>>

\* Socket close ends the session of s and of every learner whose handler is s.
ClearSessionOf(s) ==
    /\ lq' = [lq EXCEPT ![s] = <<>>]
    /\ pnc' = [pnc EXCEPT ![s] = <<>>]
    /\ pcm' = [pcm EXCEPT ![s] = <<>>]
    /\ toLog' = [toLog EXCEPT ![s] = FALSE]
    /\ syncStage' = [syncStage EXCEPT ![s] = "none"]
    /\ hstage' = [x \in Server |-> IF x = s \/ syncSource[x] = s THEN "none" ELSE hstage[x]]
    /\ nlAcked' = [nlAcked EXCEPT ![s] = {}]
    /\ zkState' = [zkState EXCEPT ![s] = "none"]

BeginElectionCore(s) ==
    /\ role' = [role EXCEPT ![s] = "looking"]
    /\ phase' = [phase EXCEPT ![s] = "election"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = Nil]
    /\ votes' = [votes EXCEPT ![s] = {s}]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ syncSource' = [syncSource EXCEPT ![s] = Nil]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = FALSE]
    /\ ExitHist(s)
    /\ ClearSessionOf(s)
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, leadersByEpoch,
                   proposed, queued, committed, applied, snapshot,
                   acked, commitCertified, messages, usedTxn,
                   syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(* FastLeaderElection.lookForLeader after any role exit (timeouts, socket   *)
(* failures, leader loss).                                                 *)
BeginElection(s) ==
    /\ up[s]
    /\ acceptedEpoch[s] < MaxEpoch
    /\ BeginElectionCore(s)

(* Follower.followLeader catch (Follower.java:130-135) after an exception   *)
(* escaped syncWithLeader; QuorumPeer.run then shuts down and goes LOOKING. *)
LearnerAbort(s) ==
    /\ up[s] /\ syncStage[s] = "failed"
    /\ BeginElectionCore(s)

(* FLE totalOrderPredicate: peer epoch (currentEpoch), then last zxid of the *)
(* data tree (getLastLoggedZxid), then id.                                 *)
HistoryAtLeast(candidate, voter) ==
    \/ currentEpoch[candidate] > currentEpoch[voter]
    \/ /\ currentEpoch[candidate] = currentEpoch[voter]
       /\ ZxidGeq(DbPos(candidate), DbPos(voter))

CastVote(voter, candidate) ==
    /\ up[voter] /\ up[candidate]
    /\ role[voter] = "looking"
    /\ HistoryAtLeast(candidate, voter)
    /\ votes' = [votes EXCEPT ![candidate] = @ \cup {voter}]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                   leadersByEpoch, histVars, commitVars, syncVars,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(* FLE quorum decision followed by Leader.getEpochToPropose. *)
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
    /\ UNCHANGED <<up, currentEpoch, votes, histVars, commitVars, syncVars,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(* QuorumPeer main loop switches a learner to FOLLOWING before discovery. *)
FollowLeader(s, l) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[l] = "leading"
    /\ role[s] = "looking"
    /\ role' = [role EXCEPT ![s] = "following"]
    /\ phase' = [phase EXCEPT ![s] = "discovery"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = l]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, votes, leadersByEpoch,
                   histVars, commitVars, syncVars,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(* Learner.registerWithLeader persists acceptedEpoch before ACKEPOCH. *)
AcceptEpoch(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "discovery"
    /\ leaderOf[s] \in Server
    /\ acceptedEpoch[s] < acceptedEpoch[leaderOf[s]]
    /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![s] = acceptedEpoch[leaderOf[s]]]
    /\ UNCHANGED <<up, role, phase, leaderOf, currentEpoch, votes,
                   leadersByEpoch, histVars, commitVars, syncVars,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(* Leader.lead: waitForEpochAck quorum, then setCurrentEpoch (Leader.java:657-658). *)
FinishDiscovery(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "discovery"
    /\ Cardinality({s \in Server : up[s] /\ acceptedEpoch[s] = acceptedEpoch[l]}) >= Quorum
    /\ currentEpoch' = [currentEpoch EXCEPT ![l] = acceptedEpoch[l]]
    /\ epochTarget' = [epochTarget EXCEPT ![l] = recovered[l]]
    /\ phase' = [phase EXCEPT ![l] = "sync"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, votes, leadersByEpoch,
                   histVars, commitVars, syncVars,
                   usedTxn, syncTarget, syncError>>
    /\ ResetRollback

(* Follower.followLeader sets SYNCHRONIZATION before syncWithLeader. *)
EnterSyncPhase(s, l) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "following" /\ leaderOf[s] = l
    /\ phase[s] = "discovery" /\ phase[l] \in {"sync", "broadcast"}
    /\ acceptedEpoch[s] = acceptedEpoch[l]
    /\ syncStage[s] = "none"
    /\ phase' = [phase EXCEPT ![s] = "sync"]
    /\ syncSource' = [syncSource EXCEPT ![s] = l]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                   leadersByEpoch, histVars, commitVars,
                   syncMode, syncJustified, lq, pnc, pcm, toLog, syncStage,
                   hstage, nlAcked, zkState,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

DiffAllowed(s, l) == IsPrefix(DbPos(s), LeaderHist(l))
TruncAllowed(s, l) == IsPrefix(LeaderHist(l), DbPos(s)) /\ LeaderHist(l) /= DbPos(s)

(***************************************************************************)
(* LearnerHandler.syncFollower (LearnerHandler.java:775-933) chooses       *)
(* DIFF/TRUNC/SNAP under the committed-log read lock, queues the diff      *)
(* (PROPOSAL+COMMIT pairs) and calls Leader.startForwarding                *)
(* (Leader.java:1294-1330): toBeApplied pairs, then outstanding PROPOSALs, *)
(* then the handler becomes a forwarding follower.  The learner's          *)
(* processing of the directive (Learner.java:560-603) is folded in: DIFF   *)
(* sets writeToTxnLog; SNAP replaces the in-memory tree; TRUNC truncates   *)
(* the log and reloads (ZKDatabase.truncateLog).                           *)
(***************************************************************************)
SelectSync(s, l, mode) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "following" /\ leaderOf[s] = l /\ role[l] = "leading"
    /\ phase[s] = "sync" /\ phase[l] \in {"sync", "broadcast"}
    /\ acceptedEpoch[s] = acceptedEpoch[l]
    /\ syncSource[s] = l /\ syncStage[s] = "none" /\ hstage[s] = "none"
    /\ mode \in SyncModes \ {"NONE"}
    /\ IF mode = "DIFF" THEN DiffAllowed(s, l)
       ELSE IF mode = "TRUNC" THEN TruncAllowed(s, l)
       ELSE ~(DiffAllowed(s, l) \/ TruncAllowed(s, l)) \/ DbPos(s) = <<>>
    /\ LET H == LeaderHist(l)
           T == LeaderTree(l)
           F == DbPos(s)
           O == Outstanding(l)
       IN
       /\ syncMode' = [syncMode EXCEPT ![s] = mode]
       /\ syncTarget' = [syncTarget EXCEPT ![s] = H]
       \* Learner.java:556-562,611: writeToTxnLog = !snapshotNeeded (DIFF only)
       /\ toLog' = [toLog EXCEPT ![s] = (mode = "DIFF")]
       /\ syncStage' = [syncStage EXCEPT ![s] = "loop"]
       /\ hstage' = [hstage EXCEPT ![s] = "fwd"]
       /\ lq' = [lq EXCEPT ![s] =
             IF mode = "DIFF" THEN PropCommitPairs(After(H, Len(F))) \o Props(O)
             ELSE IF mode = "SNAP" THEN PropCommitPairs(After(H, Len(T))) \o Props(O)
             ELSE Props(O)]
       /\ recovered' = [recovered EXCEPT ![s] =
             IF mode = "DIFF" THEN F ELSE IF mode = "SNAP" THEN T ELSE H]
       /\ IF mode = "TRUNC"
          THEN \* FileTxnSnapLog.truncateLog: the log is cut back to the leader's zxid.
               /\ durable' = [durable EXCEPT ![s] = IF IsPrefix(H, durable[s]) THEN H ELSE durable[s]]
               /\ appended' = [appended EXCEPT ![s] = IF IsPrefix(H, durable[s]) THEN H ELSE durable[s]]
               /\ queued' = [queued EXCEPT ![s] = IF IsPrefix(H, durable[s]) THEN H ELSE durable[s]]
               /\ proposed' = [proposed EXCEPT ![s] = IF IsPrefix(H, durable[s]) THEN H ELSE durable[s]]
               /\ AuthorizeRollback(s)
          ELSE /\ UNCHANGED <<durable, appended, queued, proposed>>
               /\ ResetRollback
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch, votes,
                   leadersByEpoch, committed, applied, snapshot, commitVars,
                   syncSource, syncJustified, pnc, pcm, nlAcked, zkState,
                   usedTxn, epochTarget, syncError>>

(* LearnerHandler.run queues NEWLEADER after syncFollower (and the SNAP      *)
(* stream) returns (LearnerHandler.java:591-601).                          *)
LeaderQueueNewLeader(l, s) ==
    /\ up[l] /\ role[l] = "leading"
    /\ syncSource[s] = l /\ hstage[s] = "fwd"
    /\ lq' = [lq EXCEPT ![s] = Append(@, [type |-> "NEWLEADER", ent |-> Marker(acceptedEpoch[l])])]
    /\ hstage' = [hstage EXCEPT ![s] = "nl"]
    /\ UNCHANGED <<electionVars, histVars, commitVars,
                   syncMode, syncSource, syncJustified, pnc, pcm, toLog,
                   syncStage, nlAcked, zkState,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

LearnerReading(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncStage[s] \in {"loop", "nlAcked"}
    /\ lq[s] /= <<>>

(* Learner.java:621-642 case PROPOSAL: append to packetsNotCommitted. *)
LearnerProposal(s) ==
    /\ LearnerReading(s)
    /\ Head(lq[s]).type = "PROPOSAL"
    /\ pnc' = [pnc EXCEPT ![s] = Append(@, Head(lq[s]).ent)]
    /\ lq' = [lq EXCEPT ![s] = Tail(@)]
    /\ UNCHANGED <<electionVars, histVars, commitVars,
                   syncMode, syncSource, syncJustified, pcm, toLog,
                   syncStage, hstage, nlAcked, zkState,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(***************************************************************************)
(* Learner.java:643-669 case COMMIT (unchanged code, consumer of the       *)
(* buffer the update now clears).  `pif = packetsNotCommitted.peekFirst();`*)
(* is dereferenced unconditionally (`pif.hdr.getZxid()`): an empty buffer *)
(* throws NullPointerException out of syncWithLeader.                      *)
(* UPDATE-MAP                                                              *)
(* code: quorum/Learner.java:752-758 (packetsNotCommitted.clear())         *)
(* update: Update!InteractionActions (MCLearnerCommit), Update!NoSyncException *)
(***************************************************************************)
LearnerCommit(s) ==
    /\ LearnerReading(s)
    /\ Head(lq[s]).type = "COMMIT"
    /\ lq' = [lq EXCEPT ![s] = Tail(@)]
    /\ LET e == Head(lq[s]).ent IN
       IF pnc[s] = <<>>
       THEN /\ syncStage' = [syncStage EXCEPT ![s] = "failed"]
            /\ syncError' = syncError \cup {[server |-> s, kind |-> "NPE"]}
            /\ UNCHANGED <<pnc, pcm, recovered>>
       ELSE IF ~toLog[s]
       THEN \* Learner.java:656-665: apply directly (zk.processTxn) if it is the head
            /\ IF Head(pnc[s]) = e
               THEN /\ recovered' = [recovered EXCEPT ![s] = Append(@, e)]
                    /\ pnc' = [pnc EXCEPT ![s] = Tail(@)]
               ELSE UNCHANGED <<recovered, pnc>>
            /\ UNCHANGED <<pcm, syncStage, syncError>>
       ELSE \* Learner.java:666-668: packetsCommitted.add(zxid)
            /\ pcm' = [pcm EXCEPT ![s] = Append(@, e)]
            /\ UNCHANGED <<pnc, recovered, syncStage, syncError>>
    /\ UNCHANGED <<electionVars, proposed, queued, appended, durable, committed,
                   applied, snapshot, commitVars,
                   syncMode, syncSource, syncJustified, toLog, hstage, nlAcked,
                   zkState, usedTxn, syncTarget, epochTarget>>
    /\ ResetRollback

(***************************************************************************)
(* Learner.java:726-746 case NEWLEADER, first part: takeSnapshot when      *)
(* snapshotNeeded (SNAP/TRUNC), setCurrentEpoch(newEpoch) (file write then *)
(* field), writeToTxnLog = true.                                           *)
(* UPDATE-MAP                                                              *)
(* code: quorum/Learner.java:739-746                                       *)
(* update: Update!AffectedActions (MCLearnerNewLeader), Update!EpochHistoryRecoverable *)
(***************************************************************************)
LearnerNewLeader(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncStage[s] = "loop"
    /\ lq[s] /= <<>> /\ Head(lq[s]).type = "NEWLEADER"
    /\ lq' = [lq EXCEPT ![s] = Tail(@)]
    /\ IF syncMode[s] \in {"SNAP", "TRUNC"}
       THEN /\ snapshot' = [snapshot EXCEPT ![s] = recovered[s]]
            /\ durable' = [durable EXCEPT ![s] = recovered[s]]
            /\ appended' = [appended EXCEPT ![s] = recovered[s]]
            /\ queued' = [queued EXCEPT ![s] = recovered[s]]
            /\ proposed' = [proposed EXCEPT ![s] = recovered[s]]
            /\ AuthorizeRollback(s)
       ELSE /\ UNCHANGED <<snapshot, durable, appended, queued, proposed>>
            /\ ResetRollback
    /\ currentEpoch' = [currentEpoch EXCEPT ![s] = Head(lq[s]).ent.epoch]
    /\ epochTarget' = [epochTarget EXCEPT ![s] = syncTarget[s]]
    /\ toLog' = [toLog EXCEPT ![s] = TRUE]
    /\ syncStage' = [syncStage EXCEPT ![s] = "nlEpoch"]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, votes, leadersByEpoch,
                   committed, applied, recovered, commitVars,
                   syncMode, syncSource, syncJustified, pnc, pcm, hstage,
                   nlAcked, zkState, usedTxn, syncTarget, syncError>>

(***************************************************************************)
(* NEWLEADER, second part (UPDATE): setSoTimeout, setSyncMode(NONE),       *)
(* zk.startupWithoutServing() -> request processors started, State.INITIAL.*)
(* UPDATE-MAP                                                              *)
(* code: quorum/Learner.java:749-751; ZooKeeperServer.java:673-675,682-704 *)
(* update: Update!AffectedActions (MCLearnerStartupWithoutServing)         *)
(***************************************************************************)
LearnerStartupWithoutServing(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncStage[s] = "nlEpoch"
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ zkState' = [zkState EXCEPT ![s] = "initial"]
    /\ syncStage' = [syncStage EXCEPT ![s] = "nlStarted"]
    /\ UNCHANGED <<electionVars, histVars, commitVars,
                   syncSource, syncJustified, lq, pnc, pcm, toLog, hstage,
                   nlAcked, usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(***************************************************************************)
(* NEWLEADER, third part (UPDATE): for each packetsNotCommitted entry      *)
(* fzk.logRequest -> pendingTxns.add + SyncRequestProcessor queue          *)
(* (FollowerZooKeeperServer.java:82-89).  Durability is asynchronous.      *)
(* UPDATE-MAP                                                              *)
(* code: quorum/Learner.java:752-757                                       *)
(* update: Update!AffectedActions (MCLearnerLogPending)                    *)
(***************************************************************************)
LearnerLogPending(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncStage[s] = "nlStarted"
    /\ pnc[s] /= <<>>
    /\ proposed' = [proposed EXCEPT ![s] = LogAppend(@, Head(pnc[s]))]
    /\ queued' = [queued EXCEPT ![s] = LogAppend(@, Head(pnc[s]))]
    /\ pnc' = [pnc EXCEPT ![s] = Tail(@)]
    /\ UNCHANGED <<electionVars, appended, durable, committed, applied,
                   snapshot, recovered, commitVars,
                   syncMode, syncSource, syncJustified, lq, pcm, toLog,
                   syncStage, hstage, nlAcked, zkState,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(***************************************************************************)
(* NEWLEADER, last part: packetsNotCommitted.clear() then                  *)
(* writePacket(ACK newLeaderZxid) -- without waiting for the log flush.    *)
(* UPDATE-MAP                                                              *)
(* code: quorum/Learner.java:757-760                                       *)
(* update: Update!AffectedActions (MCLearnerAckNewLeader), Update!NewLeaderAckDurable *)
(***************************************************************************)
LearnerAckNewLeader(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncStage[s] = "nlStarted"
    /\ pnc[s] = <<>>
    /\ syncSource[s] \in Server
    /\ messages' = messages \cup
         {[kind |-> "nlack", from |-> s, to |-> syncSource[s], id |-> Nil,
           epoch |-> currentEpoch[s]]}
    /\ syncStage' = [syncStage EXCEPT ![s] = "nlAcked"]
    /\ UNCHANGED <<electionVars, histVars, acked, commitCertified,
                   syncMode, syncSource, syncJustified, lq, pnc, pcm, toLog,
                   hstage, nlAcked, zkState,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(* LearnerHandler.java:614-623 -> Leader.waitForNewLeaderAck (Leader.java:1547-1586). *)
LeaderReceiveNewLeaderAck(m) ==
    /\ m \in messages /\ m.kind = "nlack"
    /\ up[m.to] /\ role[m.to] = "leading"
    /\ acceptedEpoch[m.to] = m.epoch
    /\ syncSource[m.from] = m.to /\ hstage[m.from] = "nl"
    /\ nlAcked' = [nlAcked EXCEPT ![m.to] = @ \cup {m.from}]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<electionVars, histVars, acked, commitCertified,
                   syncMode, syncSource, syncJustified, lq, pnc, pcm, toLog,
                   syncStage, hstage, zkState,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(***************************************************************************)
(* Leader.lead -> waitForNewLeaderAck quorum -> startZkServer              *)
(* (Leader.java:654-690,1497-1520).  The leader's loaded history becomes   *)
(* the epoch's committed history and is served.                            *)
(***************************************************************************)
LeaderBroadcast(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "sync"
    \* An ACK already counted by waitForNewLeaderAck stays counted even if the
    \* learner fails afterwards.
    /\ Cardinality({l} \cup nlAcked[l]) >= Quorum
    /\ LET H == recovered[l] IN
       /\ phase' = [phase EXCEPT ![l] = "broadcast"]
       /\ zkState' = [zkState EXCEPT ![l] = "running"]
       /\ committed' = [committed EXCEPT ![l] = H]
       /\ applied' = [applied EXCEPT ![l] = H]
       /\ proposed' = [proposed EXCEPT ![l] = H]
       /\ queued' = [queued EXCEPT ![l] = H]
       \* A log suffix that the in-memory tree does not contain is not part of
       \* the leader's committed log (abstraction: orphaned log suffix).
       /\ appended' = [appended EXCEPT ![l] = IF IsPrefix(durable[l], H) THEN durable[l] ELSE H]
       /\ durable' = [durable EXCEPT ![l] = IF IsPrefix(durable[l], H) THEN durable[l] ELSE H]
       /\ commitCertified' = [t \in Txn |-> commitCertified[t] \/ t \in TxnIds(H)]
       /\ IF IsPrefix(durable[l], H) /\ IsPrefix(committed[l], H) /\ IsPrefix(applied[l], H)
          THEN ResetRollback ELSE AuthorizeRollback(l)
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                   leadersByEpoch, snapshot, recovered, acked, messages,
                   syncMode, syncSource, syncJustified, lq, pnc, pcm, toLog,
                   syncStage, hstage, nlAcked,
                   usedTxn, syncTarget, epochTarget, syncError>>

(* LearnerHandler.java:635-648: after waitForStartup, queue UPTODATE. *)
LeaderQueueUpToDate(l, s) ==
    /\ Established(l)
    /\ syncSource[s] = l /\ hstage[s] = "nl" /\ s \in nlAcked[l]
    /\ lq' = [lq EXCEPT ![s] = Append(@, [type |-> "UPTODATE", ent |-> Marker(acceptedEpoch[l])])]
    /\ hstage' = [hstage EXCEPT ![s] = "utd"]
    /\ UNCHANGED <<electionVars, histVars, commitVars,
                   syncMode, syncSource, syncJustified, pnc, pcm, toLog,
                   syncStage, nlAcked, zkState,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(***************************************************************************)
(* Learner.java:711-725 case UPTODATE breaks the loop; then (762-765)      *)
(* writePacket(ack) and zk.startServing() (UPDATE: setState(RUNNING) only).*)
(* The synchronised tree becomes the served/committed state.               *)
(* UPDATE-MAP                                                              *)
(* code: quorum/Learner.java:765-767; ZooKeeperServer.java:677-680         *)
(* update: Update!AffectedActions (MCLearnerUpToDate)                      *)
(***************************************************************************)
LearnerUpToDate(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncStage[s] = "nlAcked"
    /\ lq[s] /= <<>> /\ Head(lq[s]).type = "UPTODATE"
    /\ lq' = [lq EXCEPT ![s] = Tail(@)]
    /\ zkState' = [zkState EXCEPT ![s] = "running"]
    /\ committed' = [committed EXCEPT ![s] = recovered[s]]
    /\ applied' = [applied EXCEPT ![s] = recovered[s]]
    /\ syncStage' = [syncStage EXCEPT ![s] = "serving"]
    /\ AuthorizeRollback(s)
    /\ UNCHANGED <<electionVars, proposed, queued, appended, durable, snapshot,
                   recovered, commitVars,
                   syncMode, syncSource, syncJustified, pnc, pcm, toLog, hstage,
                   nlAcked, usedTxn, syncTarget, epochTarget, syncError>>

(* Learner.java:778-782: log packets that arrived after NEWLEADER. *)
LearnerLogAfterUpToDate(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncStage[s] = "serving"
    /\ pnc[s] /= <<>>
    /\ proposed' = [proposed EXCEPT ![s] = LogAppend(@, Head(pnc[s]))]
    /\ queued' = [queued EXCEPT ![s] = LogAppend(@, Head(pnc[s]))]
    /\ pnc' = [pnc EXCEPT ![s] = Tail(@)]
    /\ UNCHANGED <<electionVars, appended, durable, committed, applied,
                   snapshot, recovered, commitVars,
                   syncMode, syncSource, syncJustified, lq, pcm, toLog,
                   syncStage, hstage, nlAcked, zkState,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(***************************************************************************)
(* Learner.java:783-784 fzk.commit(zxid) for packetsCommitted;             *)
(* FollowerZooKeeperServer.commit (98-113): empty pendingTxns -> warn and  *)
(* return; head mismatch -> System.exit(UNMATCHED_TXN_COMMIT).             *)
(***************************************************************************)
LearnerCommitAfterUpToDate(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncStage[s] = "serving"
    /\ pnc[s] = <<>> /\ pcm[s] /= <<>>
    /\ pcm' = [pcm EXCEPT ![s] = Tail(@)]
    /\ LET e == Head(pcm[s]) IN
       IF Len(committed[s]) >= Len(proposed[s])
       THEN UNCHANGED <<committed, syncStage, syncError>>
       ELSE IF proposed[s][Len(committed[s]) + 1] = e
       THEN /\ committed' = [committed EXCEPT ![s] = Append(@, e)]
            /\ UNCHANGED <<syncStage, syncError>>
       ELSE /\ syncStage' = [syncStage EXCEPT ![s] = "failed"]
            /\ syncError' = syncError \cup {[server |-> s, kind |-> "UNMATCHED_COMMIT"]}
            /\ UNCHANGED committed
    /\ UNCHANGED <<electionVars, proposed, queued, appended, durable, applied,
                   snapshot, recovered, commitVars,
                   syncMode, syncSource, syncJustified, lq, pnc, toLog,
                   hstage, nlAcked, zkState, usedTxn, syncTarget, epochTarget>>
    /\ ResetRollback

(* Follower.followLeader sets BROADCAST after syncWithLeader returns. *)
EnterBroadcast(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncStage[s] = "serving" /\ pnc[s] = <<>> /\ pcm[s] = <<>>
    /\ currentEpoch[s] = acceptedEpoch[s]
    /\ phase' = [phase EXCEPT ![s] = "broadcast"]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = TRUE]
    /\ syncStage' = [syncStage EXCEPT ![s] = "none"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                   leadersByEpoch, histVars, commitVars,
                   syncMode, syncSource, lq, pnc, pcm, toLog, hstage, nlAcked,
                   zkState, usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

\* Leader.sendPacket goes to forwardingFollowers: handlers still inside their
\* sync stream receive it in `lq`, synchronised handlers over `messages`.
StreamFollowers(l) == {s \in Server : syncSource[s] = l /\ hstage[s] \in {"fwd", "nl"}}
BcastFollowers(l) == {s \in Server : syncSource[s] = l /\ hstage[s] = "utd"}

(* ProposalRequestProcessor -> Leader.propose, then local SyncRequestProcessor. *)
Propose(l, t) ==
    /\ Established(l)
    /\ t \in Txn \ usedTxn
    /\ LET ent == EntryFor(t, currentEpoch[l]) IN
       /\ proposed' = [proposed EXCEPT ![l] = Append(@, ent)]
       /\ queued' = [queued EXCEPT ![l] = Append(@, ent)]
       /\ lq' = [s \in Server |-> IF s \in StreamFollowers(l)
                                  THEN Append(lq[s], PropPkt(ent)) ELSE lq[s]]
       /\ messages' = messages \cup
             {[kind |-> "proposal", from |-> l, to |-> s,
               id |-> t, epoch |-> currentEpoch[l]] : s \in BcastFollowers(l)}
    /\ usedTxn' = usedTxn \cup {t}
    /\ UNCHANGED <<electionVars, appended, durable, committed, applied,
                   snapshot, recovered, acked, commitCertified,
                   syncMode, syncSource, syncJustified, pnc, pcm, toLog,
                   syncStage, hstage, nlAcked, zkState,
                   syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(* Follower.processPacket PROPOSAL -> fzk.logRequest. *)
ReceiveProposal(m) ==
    /\ m \in messages /\ m.kind = "proposal"
    /\ up[m.to] /\ role[m.to] = "following" /\ phase[m.to] = "broadcast"
    /\ leaderOf[m.to] = m.from
    /\ currentEpoch[m.to] = m.epoch
    /\ LET ent == EntryFor(m.id, m.epoch) IN
       /\ proposed' = [proposed EXCEPT ![m.to] = LogAppend(@, ent)]
       /\ queued' = [queued EXCEPT ![m.to] = LogAppend(@, ent)]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<electionVars, appended, durable, committed, applied,
                   snapshot, recovered, acked, commitCertified, syncVars,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(* SyncRequestProcessor.run: ZKDatabase.append, not yet forced. *)
AppendOne(s) ==
    /\ up[s] /\ Len(appended[s]) < Len(queued[s])
    /\ LET ent == queued[s][Len(appended[s]) + 1] IN
       appended' = [appended EXCEPT ![s] = Append(@, ent)]
    /\ UNCHANGED <<electionVars, proposed, queued, durable, committed, applied,
                   snapshot, recovered, commitVars, syncVars,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(* SyncRequestProcessor.flush: ZKDatabase.commit (fsync) then the ACK        *)
(* processor.  A learner's SendAckRequestProcessor writes to the current     *)
(* leader socket; with no leader the ACK is lost but the force happened.    *)
FsyncOne(s) ==
    /\ up[s] /\ Len(durable[s]) < Len(appended[s])
    /\ LET ent == appended[s][Len(durable[s]) + 1] IN
       /\ durable' = [durable EXCEPT ![s] = Append(@, ent)]
       /\ IF role[s] = "leading"
          THEN /\ acked' = [acked EXCEPT ![ent.id] = @ \cup {s}]
               /\ messages' = messages
          ELSE /\ acked' = acked
               /\ messages' = IF leaderOf[s] \in Server /\ leaderOf[s] /= s
                              THEN messages \cup
                                   {[kind |-> "ack", from |-> s, to |-> leaderOf[s],
                                     id |-> ent.id, epoch |-> ent.epoch]}
                              ELSE messages
    /\ UNCHANGED <<electionVars, proposed, queued, appended, committed, applied,
                   snapshot, recovered, commitCertified, syncVars,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

DeliverAck(m) ==
    /\ m \in messages /\ m.kind = "ack" /\ up[m.to]
    /\ acked' = [acked EXCEPT ![m.id] = @ \cup {m.from}]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<electionVars, histVars, commitCertified, syncVars,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(* Leader.tryToCommit: quorum ACKs and in-order outstanding proposal;     *)
(* COMMIT goes to every forwarding follower (Leader.commit/sendPacket).   *)
Commit(l, t) ==
    /\ Established(l)
    /\ Len(committed[l]) < Len(proposed[l])
    /\ LET ent == proposed[l][Len(committed[l]) + 1] IN
       /\ ent.id = t
       /\ Cardinality(acked[t]) >= Quorum
       /\ committed' = [committed EXCEPT ![l] = Append(@, ent)]
       /\ commitCertified' = [commitCertified EXCEPT ![t] = TRUE]
       /\ lq' = [s \in Server |-> IF s \in StreamFollowers(l)
                                  THEN Append(lq[s], CommitPkt(ent)) ELSE lq[s]]
       /\ messages' = messages \cup
            {[kind |-> "commit", from |-> l, to |-> s,
              id |-> t, epoch |-> ent.epoch] : s \in BcastFollowers(l)}
    /\ UNCHANGED <<electionVars, proposed, queued, appended, durable, applied,
                   snapshot, recovered, acked,
                   syncMode, syncSource, syncJustified, pnc, pcm, toLog,
                   syncStage, hstage, nlAcked, zkState,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(* Follower.processPacket COMMIT -> fzk.commit (pendingTxns head). *)
ReceiveCommit(m) ==
    /\ m \in messages /\ m.kind = "commit" /\ up[m.to]
    /\ role[m.to] = "following" /\ phase[m.to] = "broadcast"
    /\ leaderOf[m.to] = m.from
    /\ currentEpoch[m.to] = m.epoch
    /\ Len(committed[m.to]) < Len(proposed[m.to])
    /\ proposed[m.to][Len(committed[m.to]) + 1] = EntryFor(m.id, m.epoch)
    /\ committed' = [committed EXCEPT ![m.to] = Append(@, EntryFor(m.id, m.epoch))]
    /\ commitCertified' = [commitCertified EXCEPT ![m.id] = TRUE]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<electionVars, proposed, queued, appended, durable, applied,
                   snapshot, recovered, acked, syncVars,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(* CommitProcessor -> FinalRequestProcessor -> ZooKeeperServer.processTxn. *)
ApplyOne(s) ==
    /\ up[s] /\ zkState[s] = "running"
    /\ Len(applied[s]) < Len(committed[s])
    /\ LET ent == committed[s][Len(applied[s]) + 1] IN
       /\ commitCertified[ent.id]
       /\ applied' = [applied EXCEPT ![s] = Append(@, ent)]
    /\ UNCHANGED <<electionVars, proposed, queued, appended, durable, committed,
                   snapshot, recovered, commitVars, syncVars,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(* Background snapshot of the applied tree. *)
TakeSnapshot(s) ==
    /\ up[s] /\ zkState[s] = "running" /\ snapshot[s] /= applied[s]
    /\ snapshot' = [snapshot EXCEPT ![s] = applied[s]]
    /\ UNCHANGED <<electionVars, proposed, queued, appended, durable, committed,
                   applied, recovered, commitVars, syncVars,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

(* Fail-stop crash: every non-forced stage and all sessions are lost. *)
Crash(s) ==
    /\ up[s]
    /\ up' = [up EXCEPT ![s] = FALSE]
    /\ role' = [role EXCEPT ![s] = "looking"]
    /\ phase' = [phase EXCEPT ![s] = "offline"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = Nil]
    /\ proposed' = [proposed EXCEPT ![s] = durable[s]]
    /\ queued' = [queued EXCEPT ![s] = durable[s]]
    /\ appended' = [appended EXCEPT ![s] = durable[s]]
    \* Retained visible state: the certified prefix of the last snapshot (a
    \* NEWLEADER snapshot may also contain not-yet-established entries).
    /\ committed' = [committed EXCEPT ![s] = CertifiedPrefix(snapshot[s])]
    /\ applied' = [applied EXCEPT ![s] = CertifiedPrefix(snapshot[s])]
    /\ recovered' = [recovered EXCEPT ![s] = <<>>]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ syncSource' = [syncSource EXCEPT ![s] = Nil]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = FALSE]
    /\ ClearSessionOf(s)
    /\ AuthorizeRollback(s)
    /\ UNCHANGED <<acceptedEpoch, currentEpoch, votes, leadersByEpoch,
                   durable, snapshot, commitVars,
                   usedTxn, syncTarget, epochTarget, syncError>>

(* QuorumPeer start: FileTxnSnapLog.restore = snapshot + forced log. *)
Restart(s) ==
    /\ ~up[s]
    /\ up' = [up EXCEPT ![s] = TRUE]
    /\ phase' = [phase EXCEPT ![s] = "election"]
    /\ recovered' = [recovered EXCEPT ![s] = durable[s]]
    /\ UNCHANGED <<role, leaderOf, acceptedEpoch, currentEpoch, votes,
                   leadersByEpoch, proposed, queued, appended, durable,
                   committed, applied, snapshot, commitVars, syncVars,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

DropMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<electionVars, histVars, acked, commitCertified, syncVars,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ ResetRollback

Next ==
    \/ \E s \in Server : BeginElection(s)
    \/ \E s \in Server : LearnerAbort(s)
    \/ \E voter, candidate \in Server : CastVote(voter, candidate)
    \/ \E s \in Server : WinElection(s)
    \/ \E s, l \in Server : FollowLeader(s, l)
    \/ \E s \in Server : AcceptEpoch(s)
    \/ \E l \in Server : FinishDiscovery(l)
    \/ \E s, l \in Server : EnterSyncPhase(s, l)
    \/ \E s, l \in Server, mode \in SyncModes \ {"NONE"} : SelectSync(s, l, mode)
    \/ \E l, s \in Server : LeaderQueueNewLeader(l, s)
    \/ \E s \in Server : LearnerProposal(s)
    \/ \E s \in Server : LearnerCommit(s)
    \/ \E s \in Server : LearnerNewLeader(s)
    \/ \E s \in Server : LearnerStartupWithoutServing(s)
    \/ \E s \in Server : LearnerLogPending(s)
    \/ \E s \in Server : LearnerAckNewLeader(s)
    \/ \E m \in messages : LeaderReceiveNewLeaderAck(m)
    \/ \E l \in Server : LeaderBroadcast(l)
    \/ \E l, s \in Server : LeaderQueueUpToDate(l, s)
    \/ \E s \in Server : LearnerUpToDate(s)
    \/ \E s \in Server : LearnerLogAfterUpToDate(s)
    \/ \E s \in Server : LearnerCommitAfterUpToDate(s)
    \/ \E s \in Server : EnterBroadcast(s)
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
    /\ messages \subseteq (Message \cup NlAckMessage)
    /\ syncMode \in [Server -> SyncModes]
    /\ syncSource \in [Server -> (Server \cup {Nil})]
    /\ syncJustified \in [Server -> BOOLEAN]
    /\ usedTxn \subseteq Txn
    /\ rollbackAuthorized \in [Server -> BOOLEAN]
    /\ lq \in [Server -> Seq(SyncPacket)]
    /\ pnc \in [Server -> Seq(Entry)]
    /\ pcm \in [Server -> Seq(Entry)]
    /\ toLog \in [Server -> BOOLEAN]
    /\ syncStage \in [Server -> SyncStages]
    /\ hstage \in [Server -> HandlerStages]
    /\ nlAcked \in [Server -> SUBSET Server]
    /\ zkState \in [Server -> ZkStates]
    /\ syncTarget \in [Server -> Seq(Entry)]
    /\ epochTarget \in [Server -> Seq(Entry)]
    /\ syncError \subseteq [server : Server, kind : SyncErrorKinds]

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

\* Snapshot clause: a serving (RUNNING) server's tree contains its snapshot.
\* A NEWLEADER SNAP/TRUNC snapshot may hold the not-yet-established history
\* of the leader; while not serving (sync, crashed, restarted) the snapshot
\* is persisted state only (see changelog Round 2, Case A).
PipelinePrefix ==
    \A s \in Server :
        /\ IsPrefix(durable[s], appended[s])
        /\ IsPrefix(appended[s], queued[s])
        /\ IsPrefix(queued[s], proposed[s])
        /\ zkState[s] = "running" => IsPrefix(snapshot[s], applied[s])

EpochHistoryConsistency ==
    /\ \A s \in Server : currentEpoch[s] <= acceptedEpoch[s]
    /\ \A s \in Server : LastEpoch(durable[s]) <= acceptedEpoch[s]

SyncCompletionJustified ==
    \A s \in Server :
        (role[s] = "following" /\ phase[s] = "broadcast") =>
          /\ syncJustified[s]
          /\ leaderOf[s] \in Server
          /\ currentEpoch[s] = acceptedEpoch[s]
          /\ zkState[s] = "running"

NoIllegalRollback ==
    \A s \in Server :
       /\ (Len(durable'[s]) >= Len(durable[s]) \/ rollbackAuthorized'[s])
       /\ (Len(committed'[s]) >= Len(committed[s]) \/ rollbackAuthorized'[s])
       /\ (Len(applied'[s]) >= Len(applied[s]) \/ rollbackAuthorized'[s])

HistoryPositionsMonotonicExceptRecovery == [][NoIllegalRollback]_allVars

Safety == TypeOK /\ ElectionSafety /\ OneActiveLeaderPerEpoch /\
          CommittedHistoriesPrefix /\ ApplyRequiresCommitCertificate /\
          PipelinePrefix /\ EpochHistoryConsistency /\ SyncCompletionJustified

ModelSymmetry == Permutations(Server)

\* Explicit finite execution depth used by the base regression config.
CanonicalDepthBound == TLCGet("level") <= 23

=============================================================================
