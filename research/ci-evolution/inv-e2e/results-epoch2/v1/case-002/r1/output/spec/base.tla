------------------------------ MODULE base ------------------------------
(***************************************************************************)
(* ZooKeeper Zab reference model -- V1 (updated source revision).          *)
(*                                                                         *)
(* Source paths are relative to zookeeper-server/src/main/java/org/apache/ *)
(* zookeeper/server/ in /work/current/.specula-output/artifact (commit     *)
(* "update").  V0 semantics are preserved except where marked UPDATE-MAP   *)
(* (source-driven change) or REPAIR (implementation-backed repair of a V0  *)
(* abstraction that the update depends on); see spec/changelog.md.         *)
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
Epoch == 0..MaxEpoch
Entry == [id : Txn, epoch : Epoch]
MsgKind == {"proposal", "ack", "commit"}
Message == [kind : MsgKind, from : Server, to : Server,
            id : Txn, epoch : Epoch]
\* UPDATE-MAP
\* code: quorum/Learner.java:760 writePacket(ACK, newLeaderZxid) ; Leader.java:1547-1572
\* update: Update!AffectedActions (FollowerSendNewLeaderAck, LeaderProcessNewLeaderAck)
NewLeaderAckMsg == [from : Server, to : Server, epoch : Epoch]
\* ZooKeeperServer.State as relevant to the update (ZooKeeperServer.java:177,
\* 669-680, 784-786): OFF = no request processors started for the current
\* role; INITIAL = startupWithoutServing (processors running, not serving);
\* RUNNING = startup()/startServing().
ZkStates == {"OFF", "INITIAL", "RUNNING"}
\* Learner progress inside the Zab-1.0 NEWLEADER branch (Learner.java:726-761).
NlStates == {"NONE", "LOGGED", "ACKED"}

Quorum == (Cardinality(Server) \div 2) + 1

VARIABLES up, role, phase, leaderOf,
          acceptedEpoch, currentEpoch,
          votes, leadersByEpoch,
          proposed, queued, appended, durable, committed, applied,
          snapshot, recovered,
          acked, commitCertified, messages,
          syncMode, syncSource, syncJustified,
          usedTxn, rollbackAuthorized,
          \* ---- V1 additions (see UPDATE-MAP / REPAIR comments) ----
          syncBuf,      \* learner packetsNotCommitted (Learner.java:559,641,706)
          syncKind,     \* sync directive of the current session (Learner.java:561-599)
          nlState,      \* learner NEWLEADER-branch progress
          nlAckMsgs,    \* NEWLEADER ACK packets in flight
          nlAcks,       \* Leader.newLeaderProposal ack set (Leader.java:1569)
          ackShadowed,  \* a txn ACK preceded this learner's NEWLEADER ACK
          zkState,      \* ZooKeeperServer.state for the current role
          certEpoch     \* ghost: epoch of the leader that first certified a txn

allVars == <<up, role, phase, leaderOf,
             acceptedEpoch, currentEpoch,
             votes, leadersByEpoch,
             proposed, queued, appended, durable, committed, applied,
             snapshot, recovered,
             acked, commitCertified, messages,
             syncMode, syncSource, syncJustified,
             usedTxn, rollbackAuthorized,
             syncBuf, syncKind, nlState, nlAckMsgs, nlAcks, ackShadowed,
             zkState, certEpoch>>

\* Variable meaning note (REPAIR, V1): `recovered` is the server's in-memory
\* ZKDatabase history -- the history reported by QuorumPeer.getLastLoggedZxid
\* (QuorumPeer.java:1257-1262) to FastLeaderElection (FastLeaderElection.java:
\* 867-873) and Learner.registerWithLeader (Learner.java:487), and loaded by
\* Leader.lead via ZooKeeperServer.loadData (ZooKeeperServer.java:480-503) when
\* the database is already initialized.  V0 used it only as tentative restart
\* state; V1 keeps that value at restart and additionally tracks shutdown
\* fast-forward and sync installation.

IsPrefix(a, b) == Len(a) <= Len(b) /\ SubSeq(b, 1, Len(a)) = a
EntryFor(id, ep) == [id |-> id, epoch |-> ep]
TxnIds(h) == {h[k].id : k \in 1..Len(h)}
LastEpoch(h) == IF Len(h) = 0 THEN 0 ELSE h[Len(h)].epoch
LastId(h) == IF Len(h) = 0 THEN Nil ELSE h[Len(h)].id
Min(a, b) == IF a < b THEN a ELSE b
CommonLen(a, b) ==
    CHOOSE k \in 0..Min(Len(a), Len(b)) :
        /\ \A i \in 1..k : a[i] = b[i]
        /\ (k = Min(Len(a), Len(b)) \/ a[k + 1] /= b[k + 1])
LCP(a, b) == SubSeq(a, 1, CommonLen(a, b))
\* zxid of the last entry: <<epoch, counter-within-epoch>>.
LastZxid(h) ==
    IF Len(h) = 0 THEN <<0, 0>>
    ELSE <<LastEpoch(h),
           Cardinality({k \in 1..Len(h) : h[k].epoch = LastEpoch(h)})>>
ZxidGeq(a, b) == a[1] > b[1] \/ (a[1] = b[1] /\ a[2] >= b[2])

\* FileTxnSnapLog.restore: latest snapshot, then log replay.
RestoredHistory(s) ==
    IF Len(snapshot[s]) > Len(durable[s]) /\ IsPrefix(durable[s], snapshot[s])
    THEN snapshot[s] ELSE durable[s]

ResetRollback == rollbackAuthorized' = [s \in Server |-> FALSE]
AuthorizeRollback(s) == rollbackAuthorized' = [x \in Server |-> x = s]

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
    /\ syncKind = [s \in Server |-> "NONE"]
    /\ nlState = [s \in Server |-> "NONE"]
    /\ nlAckMsgs = {}
    /\ nlAcks = [s \in Server |-> {}]
    /\ ackShadowed = [s \in Server |-> FALSE]
    /\ zkState = [s \in Server |-> "OFF"]
    /\ certEpoch = [t \in Txn |-> 0]

(***************************************************************************)
(* Role exit + FastLeaderElection.lookForLeader.                           *)
(* QuorumPeer.run (QuorumPeer.java:1468-1480) calls follower.shutdown() ->  *)
(* Learner.shutdown -> zk.shutdown() (Learner.java:850-863); the leader     *)
(* path calls Leader.shutdown -> zk.shutdown().                            *)
(*  - RUNNING: ZooKeeperServer.shutdown fast-forwards the in-memory DB from *)
(*    the log (ZooKeeperServer.java:836-847) and the SyncRequestProcessor   *)
(*    shutdown drains/flushes its queue (SyncRequestProcessor.java:254-271, *)
(*    LearnerZooKeeperServer.java:155-172).  Abstraction: the drained       *)
(*    entries are treated as covered by the fast-forward (the real order is *)
(*    fast-forward then drain; that pre-existing window is out of scope).   *)
(*  - INITIAL (UPDATE-MAP): canShutdown() is false (ZooKeeperServer.java:   *)
(*    784-786, 803-807; LearnerZooKeeperServer.java:156-159), so neither    *)
(*    the fast-forward nor the processor shutdown happens.  The leaked      *)
(*    SyncRequestProcessor keeps flushing what logRequest queued: either it *)
(*    has already flushed it (`flushed`) or the remainder is abstracted as  *)
(*    never reaching this server's restorable history.                    *)
(*  - OFF: no processors were started.                                      *)
(* UPDATE-MAP                                                              *)
(* code: ZooKeeperServer.java:669-680 (startupWithoutServing/startServing)  *)
(* update: Update!AffectedActions (MCBeginElection)                        *)
(***************************************************************************)
ExitPipeline(s, flushed) ==
    CASE zkState[s] = "RUNNING" ->
           /\ appended' = [appended EXCEPT ![s] = queued[s]]
           /\ durable' = [durable EXCEPT ![s] = queued[s]]
           /\ recovered' = [recovered EXCEPT ![s] = queued[s]]
           /\ UNCHANGED <<proposed, queued>>
      [] zkState[s] = "INITIAL" ->
           LET d == IF flushed THEN queued[s] ELSE durable[s] IN
           /\ durable' = [durable EXCEPT ![s] = d]
           /\ appended' = [appended EXCEPT ![s] = d]
           /\ queued' = [queued EXCEPT ![s] = d]
           /\ proposed' = [proposed EXCEPT ![s] = d]
           /\ UNCHANGED recovered
      [] OTHER ->
           UNCHANGED <<proposed, queued, appended, durable, recovered>>

BeginElection(s) ==
    /\ up[s]
    /\ acceptedEpoch[s] < MaxEpoch
    /\ \E flushed \in BOOLEAN :
          /\ (zkState[s] /= "INITIAL" => flushed)
          /\ ExitPipeline(s, flushed)
    /\ role' = [role EXCEPT ![s] = "looking"]
    /\ phase' = [phase EXCEPT ![s] = "election"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = Nil]
    /\ votes' = [votes EXCEPT ![s] = {s}]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ syncSource' = [syncSource EXCEPT ![s] = Nil]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = FALSE]
    /\ syncBuf' = [syncBuf EXCEPT ![s] = <<>>]
    /\ syncKind' = [syncKind EXCEPT ![s] = "NONE"]
    /\ nlState' = [nlState EXCEPT ![s] = "NONE"]
    /\ nlAcks' = [nlAcks EXCEPT ![s] = {}]
    /\ ackShadowed' = [ackShadowed EXCEPT ![s] = FALSE]
    /\ zkState' = [zkState EXCEPT ![s] = "OFF"]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, leadersByEpoch,
                    committed, applied, snapshot, acked, commitCertified,
                    messages, usedTxn, nlAckMsgs, certEpoch>>
    /\ ResetRollback

(* FastLeaderElection.totalOrderPredicate: peer epoch (currentEpoch,        *)
(* FastLeaderElection.java:880-884), then last zxid of the in-memory DB     *)
(* (FastLeaderElection.java:867-873 -> QuorumPeer.java:1257-1262), then id. *)
(* REPAIR (V1): V0 compared durable log length; FLE uses getLastLoggedZxid. *)
HistoryAtLeast(candidate, voter) ==
    \/ currentEpoch[candidate] > currentEpoch[voter]
    \/ /\ currentEpoch[candidate] = currentEpoch[voter]
       /\ ZxidGeq(LastZxid(recovered[candidate]), LastZxid(recovered[voter]))

CastVote(voter, candidate) ==
    /\ up[voter] /\ up[candidate]
    /\ role[voter] = "looking"
    /\ HistoryAtLeast(candidate, voter)
    /\ votes' = [votes EXCEPT ![candidate] = @ \cup {voter}]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncBuf, syncKind, nlState,
                    nlAckMsgs, nlAcks, ackShadowed, zkState, certEpoch>>
    /\ ResetRollback

(* FLE quorum decision followed by Leader.lead: zk.loadData() exposes the   *)
(* already-initialized in-memory DB (ZooKeeperServer.java:480-503) and      *)
(* Leader.getEpochToPropose.  REPAIR (V1): the leader's history is the      *)
(* in-memory DB it loaded, not an unchanged pipeline variable.              *)
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
    /\ proposed' = [proposed EXCEPT ![candidate] = recovered[candidate]]
    /\ queued' = [queued EXCEPT ![candidate] = recovered[candidate]]
    /\ nlAcks' = [nlAcks EXCEPT ![candidate] = {}]
    /\ UNCHANGED <<up, currentEpoch, votes, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncBuf, syncKind, nlState,
                    nlAckMsgs, ackShadowed, zkState, certEpoch>>
    /\ ResetRollback

(* QuorumPeer main loop switches a learner to FOLLOWING before Zab discovery. *)
FollowLeader(s, l) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[l] = "leading"
    /\ role[s] = "looking"
    /\ role' = [role EXCEPT ![s] = "following"]
    /\ phase' = [phase EXCEPT ![s] = "discovery"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = l]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, votes, leadersByEpoch,
                    proposed, queued, appended, durable, committed, applied,
                    snapshot, recovered, acked, commitCertified, messages,
                    syncMode, syncSource, syncJustified, usedTxn, syncBuf,
                    syncKind, nlState, nlAckMsgs, nlAcks, ackShadowed,
                    zkState, certEpoch>>
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
                    syncJustified, usedTxn, syncBuf, syncKind, nlState,
                    nlAckMsgs, nlAcks, ackShadowed, zkState, certEpoch>>
    /\ ResetRollback

(* Leader.waitForEpochAck completes after a participant quorum;            *)
(* Leader.java:657-660 then persists currentEpoch and enters SYNCHRONIZATION. *)
FinishDiscovery(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "discovery"
    /\ Cardinality({s \in Server : up[s] /\ acceptedEpoch[s] = acceptedEpoch[l]}) >= Quorum
    /\ currentEpoch' = [currentEpoch EXCEPT ![l] = acceptedEpoch[l]]
    /\ phase' = [phase EXCEPT ![l] = "sync"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncBuf, syncKind, nlState,
                    nlAckMsgs, nlAcks, ackShadowed, zkState, certEpoch>>
    /\ ResetRollback

(* LearnerHandler.syncFollower compares the learner's reported last zxid     *)
(* (registerWithLeader -> getLastLoggedZxid, i.e. `recovered`) with the      *)
(* leader's history (LearnerHandler.java:775-932).                          *)
DiffAllowed(s, l) == IsPrefix(recovered[s], proposed[l])
TruncAllowed(s, l) == IsPrefix(proposed[l], recovered[s])
\* Committed part of the leader history: during establishment the whole
\* loaded history is the initial history; in broadcast, the committed log.
LeaderCommittedPrefix(l) ==
    IF phase[l] = "broadcast" THEN committed[l] ELSE proposed[l]

(* QuorumPeer exposes SYNCHRONIZATION before the mode packet is consumed. *)
EnterSyncPhase(s, l) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "following" /\ leaderOf[s] = l
    /\ phase[s] = "discovery" /\ phase[l] \in {"sync", "broadcast"}
    \* Learner.registerWithLeader persists the proposed epoch before the
    \* learner can consume a synchronization directive.
    /\ acceptedEpoch[s] = acceptedEpoch[l]
    /\ phase' = [phase EXCEPT ![s] = "sync"]
    /\ syncSource' = [syncSource EXCEPT ![s] = l]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncJustified,
                    usedTxn, syncBuf, syncKind, nlState, nlAckMsgs, nlAcks,
                    ackShadowed, zkState, certEpoch>>
    /\ ResetRollback

(***************************************************************************)
(* LearnerHandler.syncFollower chooses DIFF/TRUNC/SNAP under the DB log     *)
(* lock and queues the stream; Learner.syncWithLeader consumes the          *)
(* directive (Learner.java:561-599) and buffers the streamed proposals in   *)
(* packetsNotCommitted (Learner.java:621-642, 689-709).                     *)
(*  - DIFF: nothing applied or logged yet (writeToTxnLog=true).            *)
(*  - TRUNC: ZKDatabase.truncateLog truncates the log and reloads the DB.   *)
(*  - SNAP: deserializeSnapshot replaces the in-memory DB only.            *)
(* REPAIR (V1): V0 installed the leader's durable history atomically at a  *)
(* later CompleteSync; V1 keeps the directive effect here and moves         *)
(* persistence to the NEWLEADER branch where the source performs it.       *)
(***************************************************************************)
SelectSync(s, l, mode) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "following" /\ leaderOf[s] = l
    /\ phase[s] = "sync" /\ phase[l] \in {"sync", "broadcast"}
    /\ role[l] = "leading"
    /\ syncSource[s] = l
    /\ syncKind[s] = "NONE" /\ nlState[s] = "NONE"
    /\ acceptedEpoch[s] = acceptedEpoch[l]
    /\ mode \in SyncModes \ {"NONE"}
    /\ IF mode = "DIFF" THEN DiffAllowed(s, l)
       ELSE IF mode = "TRUNC" THEN TruncAllowed(s, l)
       ELSE ~(DiffAllowed(s, l) \/ TruncAllowed(s, l)) \/ recovered[s] = <<>>
    /\ syncMode' = [syncMode EXCEPT ![s] = mode]
    /\ syncKind' = [syncKind EXCEPT ![s] = mode]
    /\ CASE mode = "DIFF" ->
              \* Learner.java:561-564; LearnerHandler queues PROPOSAL(+COMMIT)
              /\ syncBuf' = [syncBuf EXCEPT ![s] =
                     SubSeq(proposed[l], Len(recovered[s]) + 1, Len(proposed[l]))]
              /\ UNCHANGED <<proposed, queued, appended, durable, recovered>>
              /\ ResetRollback
         [] mode = "TRUNC" ->
              \* Learner.java:587-597; ZKDatabase.truncateLog
              LET d == IF IsPrefix(proposed[l], durable[s]) THEN proposed[l]
                       ELSE durable[s] IN
              /\ durable' = [durable EXCEPT ![s] = d]
              /\ appended' = [appended EXCEPT ![s] = d]
              /\ queued' = [queued EXCEPT ![s] = d]
              /\ proposed' = [proposed EXCEPT ![s] = d]
              /\ recovered' = [recovered EXCEPT ![s] = proposed[l]]
              /\ syncBuf' = [syncBuf EXCEPT ![s] = <<>>]
              /\ AuthorizeRollback(s)
         [] OTHER ->
              \* Learner.java:565-586; deserializeSnapshot (in memory only)
              LET base == LeaderCommittedPrefix(l) IN
              /\ recovered' = [recovered EXCEPT ![s] = base]
              /\ syncBuf' = [syncBuf EXCEPT ![s] =
                     SubSeq(proposed[l], Len(base) + 1, Len(proposed[l]))]
              /\ UNCHANGED <<proposed, queued, appended, durable>>
              /\ ResetRollback
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, committed, applied, snapshot,
                    acked, commitCertified, messages, syncSource,
                    syncJustified, usedTxn, nlState, nlAckMsgs, nlAcks,
                    ackShadowed, zkState, certEpoch>>

(***************************************************************************)
(* UPDATE-MAP                                                              *)
(* code: quorum/Learner.java:726-757 (NEWLEADER branch, new revision);     *)
(*       ZooKeeperServer.java:673-675 startupWithoutServing;               *)
(*       quorum/FollowerZooKeeperServer.java:82-89 logRequest              *)
(* update: Update!AffectedActions (MCFollowerProcessNewLeader)             *)
(* In order: takeSnapshot(syncSnapshot) when SNAP/TRUNC (synchronous,       *)
(* Learner.java:739-741); setCurrentEpoch(newEpoch) (Learner.java:743);     *)
(* setSyncMode(NONE) (Learner.java:750, moved here by the update);          *)
(* zk.startupWithoutServing() (Learner.java:751, state INITIAL);            *)
(* logRequest for every packetsNotCommitted entry (Learner.java:752-757):   *)
(* pendingTxns.add + SyncRequestProcessor.processRequest, which only        *)
(* enqueues (SyncRequestProcessor.java:273-278).  Appending and fsync are   *)
(* later, independent SyncRequestProcessor steps (AppendOne/FsyncOne).      *)
(* A crash anywhere inside this branch leaves the same restorable state as  *)
(* a crash immediately after it (nothing here is made durable except the    *)
(* epoch and the SNAP/TRUNC snapshot), so the branch is one atomic step;   *)
(* the ACK write is split out because the started SyncRequestProcessor can  *)
(* interleave with it.                                                      *)
(***************************************************************************)
FollowerProcessNewLeader(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncMode[s] /= "NONE" /\ syncKind[s] /= "NONE"
    /\ nlState[s] = "NONE"
    /\ syncSource[s] \in Server
    /\ LET l == syncSource[s] IN
       /\ leaderOf[s] = l
       /\ up[l] /\ role[l] = "leading"
       \* The selected sync and NEWLEADER exchange are bound to one epoch.
       /\ acceptedEpoch[s] = acceptedEpoch[l]
    /\ LET hist == recovered[s] \o syncBuf[s]
           d == IF syncKind[s] \in {"SNAP", "TRUNC"} THEN recovered[s]
                ELSE durable[s] IN
       /\ durable' = [durable EXCEPT ![s] = d]
       /\ appended' = [appended EXCEPT ![s] = d]
       /\ queued' = [queued EXCEPT ![s] = hist]
       /\ proposed' = [proposed EXCEPT ![s] = hist]
    /\ currentEpoch' = [currentEpoch EXCEPT ![s] = acceptedEpoch[s]]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ zkState' = [zkState EXCEPT ![s] = "INITIAL"]
    /\ syncBuf' = [syncBuf EXCEPT ![s] = <<>>]
    /\ nlState' = [nlState EXCEPT ![s] = "LOGGED"]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = TRUE]
    /\ IF syncKind[s] = "SNAP" THEN AuthorizeRollback(s) ELSE ResetRollback
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, votes,
                    leadersByEpoch, committed, applied, snapshot, recovered,
                    acked, commitCertified, messages, syncSource, usedTxn,
                    syncKind, nlAckMsgs, nlAcks, ackShadowed, certEpoch>>

(* UPDATE-MAP                                                              *)
(* code: quorum/Learner.java:760 writePacket(new QuorumPacket(Leader.ACK,  *)
(*       newLeaderZxid, null, null), true) -- now after logRequest only.   *)
(* update: Update!AffectedActions (MCFollowerSendNewLeaderAck)             *)
FollowerSendNewLeaderAck(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ nlState[s] = "LOGGED"
    /\ leaderOf[s] \in Server
    /\ nlAckMsgs' = nlAckMsgs \cup
          {[from |-> s, to |-> leaderOf[s], epoch |-> currentEpoch[s]]}
    /\ nlState' = [nlState EXCEPT ![s] = "ACKED"]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncBuf, syncKind, nlAcks,
                    ackShadowed, zkState, certEpoch>>
    /\ ResetRollback

(* LearnerHandler reads the first packet after NEWLEADER as the NEWLEADER   *)
(* ACK (LearnerHandler.java:606-623) and Leader.waitForNewLeaderAck counts  *)
(* it only when its zxid equals newLeaderZxid (Leader.java:1547-1572).  If   *)
(* the learner's SendAckRequestProcessor wrote a txn ACK first on the same  *)
(* TCP stream (`ackShadowed`), that txn ACK is consumed here and rejected   *)
(* as "from a different epoch"; the real NEWLEADER ACK later reaches        *)
(* Leader.processAck, which ignores zxid low-bits 0 (Leader.java:988-994).  *)
(* UPDATE-MAP                                                              *)
(* code: quorum/Learner.java:751-760 (processors started before the ACK)   *)
(* update: Update!AffectedActions (MCLeaderProcessNewLeaderAck)            *)
LeaderProcessNewLeaderAck(m) ==
    /\ m \in nlAckMsgs
    /\ up[m.to] /\ role[m.to] = "leading"
    /\ acceptedEpoch[m.to] = m.epoch
    /\ nlAcks' = IF phase[m.to] = "sync" /\ ~ackShadowed[m.from]
                 THEN [nlAcks EXCEPT ![m.to] = @ \cup {m.from}]
                 ELSE nlAcks
    /\ nlAckMsgs' = nlAckMsgs \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncBuf, syncKind, nlState,
                    ackShadowed, zkState, certEpoch>>
    /\ ResetRollback

(***************************************************************************)
(* Leader.lead: waitForNewLeaderAck(self) and a NEWLEADER quorum           *)
(* (Leader.java:663-686), then startZkServer (Leader.java:688,1497) and     *)
(* BROADCAST (Leader.java:712).  The loaded initial history becomes the     *)
(* committed, served state: it is certified here.                         *)
(* REPAIR (V1): V0 gated this on followers having entered BROADCAST; the   *)
(* source gates it on NEWLEADER ACKs and followers enter BROADCAST only     *)
(* after UPTODATE, which LearnerHandler sends after this point              *)
(* (LearnerHandler.java:623-648).                                           *)
(* UPDATE-MAP (repair the update depends on)                               *)
(* code: quorum/Leader.java:663-712,1547-1572                              *)
(* update: Update!AffectedActions (MCLeaderBroadcast)                      *)
(***************************************************************************)
LeaderBroadcast(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "sync"
    /\ Cardinality(nlAcks[l] \cup {l}) >= Quorum
    /\ phase' = [phase EXCEPT ![l] = "broadcast"]
    /\ zkState' = [zkState EXCEPT ![l] = "RUNNING"]
    /\ committed' = [committed EXCEPT ![l] = proposed[l]]
    /\ applied' = [applied EXCEPT ![l] = proposed[l]]
    /\ snapshot' = [snapshot EXCEPT ![l] = LCP(snapshot[l], proposed[l])]
    /\ commitCertified' = [t \in Txn |-> commitCertified[t] \/ t \in TxnIds(proposed[l])]
    /\ certEpoch' = [t \in Txn |->
                       IF certEpoch[t] = 0 /\ t \in TxnIds(proposed[l])
                       THEN currentEpoch[l] ELSE certEpoch[t]]
    /\ AuthorizeRollback(l)
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, recovered, acked, messages, syncMode,
                    syncSource, syncJustified, usedTxn, syncBuf, syncKind,
                    nlState, nlAckMsgs, nlAcks, ackShadowed>>

(***************************************************************************)
(* UPDATE-MAP                                                              *)
(* code: quorum/Learner.java:711-725 (UPTODATE), 765-785 (ACK, new         *)
(*       zk.startServing(), commit packetsCommitted); Follower.java:110    *)
(* update: Update!AffectedActions (MCFollowerProcessUpToDate)              *)
(* LearnerHandler queues UPTODATE only after its waitForNewLeaderAck call   *)
(* returns and the leader has started (LearnerHandler.java:623-648), i.e.   *)
(* once the leader is in BROADCAST -- whether or not this learner's ACK was *)
(* counted.  Synced entries committed by the leader are handed to the       *)
(* CommitProcessor; visible state is the certified common prefix.          *)
(***************************************************************************)
FollowerProcessUpToDate(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ nlState[s] = "ACKED"
    /\ leaderOf[s] \in Server
    /\ LET l == leaderOf[s] IN
       /\ up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
       /\ acceptedEpoch[l] = acceptedEpoch[s]
       /\ LET c == LCP(committed[l], proposed[s])
              a == LCP(applied[l], c) IN
          /\ committed' = [committed EXCEPT ![s] = c]
          /\ applied' = [applied EXCEPT ![s] = a]
          /\ snapshot' = [snapshot EXCEPT ![s] = LCP(snapshot[s], a)]
    /\ phase' = [phase EXCEPT ![s] = "broadcast"]
    /\ zkState' = [zkState EXCEPT ![s] = "RUNNING"]
    /\ nlState' = [nlState EXCEPT ![s] = "NONE"]
    /\ syncKind' = [syncKind EXCEPT ![s] = "NONE"]
    /\ AuthorizeRollback(s)
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, recovered, acked, commitCertified, messages,
                    syncMode, syncSource, syncJustified, usedTxn, syncBuf,
                    nlAckMsgs, nlAcks, ackShadowed, certEpoch>>

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
                    syncMode, syncSource, syncJustified, syncBuf, syncKind,
                    nlState, nlAckMsgs, nlAcks, ackShadowed, zkState,
                    certEpoch>>
    /\ ResetRollback

(* Follower.processPacket PROPOSAL -> FollowerZooKeeperServer.logRequest. *)
ReceiveProposal(m) ==
    /\ m \in messages /\ m.kind = "proposal"
    /\ up[m.to] /\ role[m.to] = "following" /\ phase[m.to] = "broadcast"
    /\ leaderOf[m.to] = m.from
    \* A learner's packet stream reaches broadcast only for its synchronized
    \* current epoch; a stale connection cannot enqueue a later-epoch proposal.
    /\ currentEpoch[m.to] = m.epoch
    /\ LET ent == EntryFor(m.id, m.epoch) IN
       \* REPAIR (V1): Leader.startForwarding (Leader.java:1294-1325) forwards
       \* only zxids above the learner's synced position, and the learner
       \* handler queue is FIFO; a learner therefore receives the leader's
       \* next entry, never a duplicate of a synced one or a reordered one.
       /\ IsPrefix(Append(proposed[m.to], ent), proposed[m.from])
       /\ proposed' = [proposed EXCEPT ![m.to] = Append(@, ent)]
       /\ queued' = [queued EXCEPT ![m.to] = Append(@, ent)]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, appended, durable, committed,
                    applied, snapshot, recovered, acked, commitCertified,
                    syncMode, syncSource, syncJustified, usedTxn, syncBuf,
                    syncKind, nlState, nlAckMsgs, nlAcks, ackShadowed,
                    zkState, certEpoch>>
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
                    syncJustified, usedTxn, syncBuf, syncKind, nlState,
                    nlAckMsgs, nlAcks, ackShadowed, zkState, certEpoch>>
    /\ ResetRollback

(* FileTxnLog.commit forces an appended entry; ACK is only created afterward *)
(* (SyncRequestProcessor.java:227-252 -> SendAckRequestProcessor).          *)
(* UPDATE-MAP: in the new revision the learner's processors already run in  *)
(* the NEWLEADER branch, so a txn ACK can be written before the NEWLEADER   *)
(* ACK (ackShadowed).                                                       *)
(* code: quorum/Learner.java:751-760; quorum/SendAckRequestProcessor.java   *)
(* update: Update!InteractionActions (MCFsyncOne)                          *)
FsyncOne(s) ==
    /\ up[s] /\ Len(durable[s]) < Len(appended[s])
    /\ LET ent == appended[s][Len(durable[s]) + 1] IN
       /\ durable' = [durable EXCEPT ![s] = Append(@, ent)]
       /\ IF role[s] = "leading"
          THEN /\ acked' = [acked EXCEPT ![ent.id] = @ \cup {s}]
               /\ messages' = messages
               /\ ackShadowed' = ackShadowed
          ELSE /\ leaderOf[s] \in Server
               /\ acked' = acked
               /\ messages' = messages \cup
                    {[kind |-> "ack", from |-> s, to |-> leaderOf[s],
                      id |-> ent.id, epoch |-> ent.epoch]}
               /\ ackShadowed' =
                    IF phase[s] = "sync" /\ nlState[s] = "LOGGED"
                    THEN [ackShadowed EXCEPT ![s] = TRUE]
                    ELSE ackShadowed
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    committed, applied, snapshot, recovered,
                    commitCertified, syncMode, syncSource,
                    syncJustified, usedTxn, syncBuf, syncKind, nlState,
                    nlAckMsgs, nlAcks, zkState, certEpoch>>
    /\ ResetRollback

DeliverAck(m) ==
    /\ m \in messages /\ m.kind = "ack" /\ up[m.to]
    /\ acked' = [acked EXCEPT ![m.id] = @ \cup {m.from}]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered,
                    commitCertified, syncMode, syncSource, syncJustified,
                    usedTxn, syncBuf, syncKind, nlState, nlAckMsgs, nlAcks,
                    ackShadowed, zkState, certEpoch>>
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
                           IF @ = 0 THEN currentEpoch[l] ELSE @]
       /\ messages' = messages \cup
            {[kind |-> "commit", from |-> l, to |-> s,
              id |-> t, epoch |-> ent.epoch] : s \in Server \ {l}}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, applied, snapshot, recovered, acked, syncMode,
                    syncSource, syncJustified, usedTxn, syncBuf, syncKind,
                    nlState, nlAckMsgs, nlAcks, ackShadowed, zkState>>
    /\ ResetRollback

(* A broadcast COMMIT packet (Follower.java:204-213) carries the leader's   *)
(* quorum decision.  REPAIR (V1): COMMIT packets received during the sync   *)
(* loop are buffered in packetsCommitted (Learner.java:643-669) and handled *)
(* by FollowerProcessUpToDate; this action is the broadcast-phase path.    *)
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
                    syncSource, syncJustified, usedTxn, syncBuf, syncKind,
                    nlState, nlAckMsgs, nlAcks, ackShadowed, zkState,
                    certEpoch>>
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
                    syncJustified, usedTxn, syncBuf, syncKind, nlState,
                    nlAckMsgs, nlAcks, ackShadowed, zkState, certEpoch>>
    /\ ResetRollback

(* Snapshot captures an applied prefix and is named by lastProcessedZxid. *)
TakeSnapshot(s) ==
    /\ up[s] /\ snapshot[s] /= applied[s]
    /\ snapshot' = [snapshot EXCEPT ![s] = applied[s]]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncBuf, syncKind, nlState,
                    nlAckMsgs, nlAcks, ackShadowed, zkState, certEpoch>>
    /\ ResetRollback

(* Crash drops non-durable queues and every volatile object; the epoch      *)
(* files, the forced log, and snapshots persist.                           *)
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
    /\ syncKind' = [syncKind EXCEPT ![s] = "NONE"]
    /\ nlState' = [nlState EXCEPT ![s] = "NONE"]
    /\ nlAcks' = [nlAcks EXCEPT ![s] = {}]
    /\ ackShadowed' = [ackShadowed EXCEPT ![s] = FALSE]
    /\ zkState' = [zkState EXCEPT ![s] = "OFF"]
    \* REPAIR (V1): FLE vote tallies are volatile (FastLeaderElection
    \* recvset is per lookForLeader call); a restarted peer starts a new round.
    /\ votes' = [votes EXCEPT ![s] = {}]
    /\ AuthorizeRollback(s)
    /\ UNCHANGED <<acceptedEpoch, currentEpoch, leadersByEpoch,
                    durable, snapshot, acked, commitCertified, messages,
                    usedTxn, nlAckMsgs, certEpoch>>

(* QuorumPeer start -> loadDataBase -> FileTxnSnapLog.restore: snapshot then *)
(* durable log replay becomes the in-memory DB used for the next vote.      *)
Restart(s) ==
    /\ ~up[s]
    /\ up' = [up EXCEPT ![s] = TRUE]
    /\ phase' = [phase EXCEPT ![s] = "election"]
    /\ recovered' = [recovered EXCEPT ![s] = RestoredHistory(s)]
    /\ UNCHANGED <<role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, acked, commitCertified,
                    messages, syncMode, syncSource, syncJustified, usedTxn,
                    syncBuf, syncKind, nlState, nlAckMsgs, nlAcks,
                    ackShadowed, zkState, certEpoch>>
    /\ ResetRollback

DropMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, syncMode, syncSource, syncJustified,
                    usedTxn, syncBuf, syncKind, nlState, nlAckMsgs, nlAcks,
                    ackShadowed, zkState, certEpoch>>
    /\ ResetRollback

DropNewLeaderAck(m) ==
    /\ m \in nlAckMsgs
    /\ nlAckMsgs' = nlAckMsgs \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, syncBuf, syncKind, nlState,
                    nlAcks, ackShadowed, zkState, certEpoch>>
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
    \/ \E s \in Server : FollowerProcessNewLeader(s)
    \/ \E s \in Server : FollowerSendNewLeaderAck(s)
    \/ \E m \in nlAckMsgs : LeaderProcessNewLeaderAck(m)
    \/ \E l \in Server : LeaderBroadcast(l)
    \/ \E s \in Server : FollowerProcessUpToDate(s)
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
    \/ \E m \in nlAckMsgs : DropNewLeaderAck(m)

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
    /\ syncBuf \in [Server -> Seq(Entry)]
    /\ syncKind \in [Server -> SyncModes]
    /\ nlState \in [Server -> NlStates]
    /\ nlAckMsgs \subseteq NewLeaderAckMsg
    /\ nlAcks \in [Server -> SUBSET Server]
    /\ ackShadowed \in [Server -> BOOLEAN]
    /\ zkState \in [Server -> ZkStates]
    /\ certEpoch \in [Txn -> Epoch]

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
ModelSymmetry == Permutations(Server)

\* Canonical TLC runs are bounded by this explicit finite execution depth.
CanonicalDepthBound == TLCGet("level") <= 23

=============================================================================
