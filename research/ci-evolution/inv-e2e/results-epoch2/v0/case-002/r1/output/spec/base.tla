------------------------------ MODULE base ------------------------------
(***************************************************************************)
(* ZooKeeper Zab reference model, updated for the `update` revision        *)
(* (artifact commit 2efbdfc).  Source paths are relative to                *)
(* zookeeper-server/src/main/java/org/apache/zookeeper/server/.            *)
(*                                                                         *)
(* Incremental changes versus the exact-old prior suite (see               *)
(* ../analysis-report.md section "Incremental update" and changelog.md):   *)
(*  - source delta: Learner.syncWithLeader now starts the follower server  *)
(*    without serving, logs buffered sync proposals and only then ACKs     *)
(*    NEWLEADER; UPTODATE only starts serving (Learner.java:726-786,       *)
(*    ZooKeeperServer.java:669-704).                                       *)
(*  - repairs of prior abstractions needed to observe the update: the      *)
(*    learner sync buffer, NEWLEADER-ACK barrier, leader establishment     *)
(*    committing its recovered tree, data tree (lastLoggedZxid) versus     *)
(*    txn log, server state INITIAL/RUNNING and the shutdown guard.        *)
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
\* ZooKeeperServer.State projection for the current role instance
\* (ZooKeeperServer.java:177, :669-704, :765-793).  "OFF" = not started or
\* abandoned instance.
ZkStates == {"OFF", "INITIAL", "RUNNING"}
\* Learner.syncWithLeader progress (Learner.java:546-786).
LearnerSteps == {"none", "synced", "epochPersisted", "started", "acked",
                 "serving"}
Epoch == 0..MaxEpoch
\* A transaction entry carries its zxid as (epoch, counter).
Entry == [id : Txn, epoch : Epoch, ctr : Nat \ {0}]
MsgKind == {"proposal", "ack", "commit"}
Message == [kind : MsgKind, from : Server, to : Server, ent : Entry]

Quorum == (Cardinality(Server) \div 2) + 1

VARIABLES up, role, phase, leaderOf,
          acceptedEpoch, currentEpoch,
          votes, leadersByEpoch,
          \* role history (leader proposals / follower proposal stream)
          proposed,
          \* txn-log pipeline: queued (SyncRequestProcessor) >= appended >= durable
          queued, appended, durable,
          committed,          \* commit knowledge of the active role instance
          applied,            \* in-memory DataTree history (lastLoggedZxid)
          snapshot,           \* latest snapshot content
          acked, commitCertified, messages,
          syncMode, syncSource, syncJustified,
          pending,            \* Learner packetsNotCommitted
          syncCommits,        \* Learner packetsCommitted
          zkState,            \* ZooKeeperServer state of the role instance
          learnerStep,        \* Learner.syncWithLeader progress
          nlAcks,             \* Leader newLeaderProposal ack set
          usedTxn, rollbackAuthorized,
          maxCommitted,       \* ghost: longest history committed by a quorum
          ackedHist,          \* ghost: history attested by last NEWLEADER ACK
          treeFloor           \* DataTree lastProcessedZxid set without a txn

serverVars == <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                votes, leadersByEpoch>>
logVars == <<proposed, queued, appended, durable, committed, applied,
             snapshot>>
syncVars == <<syncMode, syncSource, syncJustified, pending, syncCommits,
              zkState, learnerStep, nlAcks>>
allVars == <<up, role, phase, leaderOf,
             acceptedEpoch, currentEpoch,
             votes, leadersByEpoch,
             proposed, queued, appended, durable, committed, applied,
             snapshot,
             acked, commitCertified, messages,
             syncMode, syncSource, syncJustified,
             pending, syncCommits, zkState, learnerStep, nlAcks,
             usedTxn, rollbackAuthorized, maxCommitted, ackedHist, treeFloor>>

-----------------------------------------------------------------------------
(* Helpers *)

IsPrefix(a, b) == Len(a) <= Len(b) /\ SubSeq(b, 1, Len(a)) = a
Comparable(a, b) == IsPrefix(a, b) \/ IsPrefix(b, a)
Range(h) == {h[k] : k \in 1..Len(h)}
TxnIds(h) == {h[k].id : k \in 1..Len(h)}
Suffix(h, n) == IF n >= Len(h) THEN <<>> ELSE SubSeq(h, n + 1, Len(h))
LastEpoch(h) == IF Len(h) = 0 THEN 0 ELSE h[Len(h)].epoch

Zx(e, c) == [epoch |-> e, ctr |-> c]
NoZxid == Zx(0, 0)
ZxOf(ent) == Zx(ent.epoch, ent.ctr)
LastZ(h) == IF Len(h) = 0 THEN NoZxid ELSE ZxOf(h[Len(h)])
ZxidGT(a, b) == a.epoch > b.epoch \/ (a.epoch = b.epoch /\ a.ctr > b.ctr)
ZxidGE(a, b) == ~ZxidGT(b, a)
MaxZ(a, b) == IF ZxidGT(a, b) THEN a ELSE b

\* Index of the first log entry whose zxid is greater than z
\* (FileTxnLog.FileTxnIterator.init skips entries below the start zxid and
\* then returns the remaining file suffix in file order).
FirstAfter(h, z) ==
    IF \E k \in 1..Len(h) : ZxidGT(ZxOf(h[k]), z)
    THEN CHOOSE k \in 1..Len(h) : /\ ZxidGT(ZxOf(h[k]), z)
                                 /\ \A j \in 1..(k - 1) : ~ZxidGT(ZxOf(h[j]), z)
    ELSE Len(h) + 1
LogFrom(h, z) == SubSeq(h, FirstAfter(h, z), Len(h))

\* FileTxnSnapLog.restore (persistence/FileTxnSnapLog.java:243-304):
\* latest snapshot, then fastForwardFromEdits replays the log suffix.
Restore(snap, log) == snap \o LogFrom(log, LastZ(snap))
\* ZKDatabase.fastForwardDataBase (ZKDatabase.java:300) on an existing tree:
\* FileTxnSnapLog.fastForwardFromEdits reads the log from the DataTree's
\* lastProcessedZxid + 1, which may be a marker without a txn (LastLogged).
FastForward(tree, from, log) == tree \o LogFrom(log, from)

\* FileTxnLog.truncate (persistence/FileTxnLog.java:455): keep the log up to
\* and including the first entry at or after the target zxid.
TruncateLog(h, z) ==
    IF \E k \in 1..Len(h) : ZxidGE(ZxOf(h[k]), z)
    THEN SubSeq(h, 1, CHOOSE k \in 1..Len(h) :
                        /\ ZxidGE(ZxOf(h[k]), z)
                        /\ \A j \in 1..(k - 1) : ~ZxidGE(ZxOf(h[j]), z))
    ELSE h

\* Leader.propose / ZooKeeperServer.getNextZxid: counters restart per epoch.
NextCtr(h, ep) == 1 + Cardinality({k \in 1..Len(h) : h[k].epoch = ep})

\* Ghost update: record the longest quorum-committed history.
GrowGhost(g, h) == IF IsPrefix(g, h) THEN h ELSE g

ResetRollback == rollbackAuthorized' = [s \in Server |-> FALSE]

\* FLE votes live for one election round (FastLeaderElection.lookForLeader
\* recvset/proposals): a peer that leaves its role, crashes or reloads its
\* database withdraws every vote it cast and every vote it collected.
\* [repair, Case B: prior model let WinElection reuse votes of older rounds]
ForgetVotes(s) == [c \in Server |-> IF c = s THEN {} ELSE votes[c] \ {s}]

\* QuorumPeer.getLastLoggedZxid = ZKDatabase.getDataTreeLastProcessedZxid
\* (quorum/QuorumPeer.java:1257-1262): the last applied txn, or a marker set
\* by Leader.startZkServer (quorum/Leader.java:1536) or by SNAP/TRUNC sync
\* (quorum/Learner.java:583, :597).
LastLogged(s) == MaxZ(treeFloor[s], LastZ(applied[s]))

\* Learners that the leader forwards proposals/commits to
\* (LearnerHandler.java:920 startForwarding inside syncFollower).
Forwarding(l) == {s \in Server \ {l} : /\ role[s] = "following"
                                      /\ leaderOf[s] = l
                                      /\ syncSource[s] = l
                                      /\ syncJustified[s]}

\* LearnerHandler.syncFollower uses the leader's committedLog
\* (ZKDatabase.committedLog): its whole loaded tree before establishment,
\* its quorum-committed history afterwards (toBeApplied entries are sent
\* with COMMIT by startForwarding).
SyncCommittedHist(l) == IF zkState[l] = "RUNNING" THEN committed[l]
                        ELSE proposed[l]

-----------------------------------------------------------------------------
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
    /\ acked = [t \in Txn |-> {}]
    /\ commitCertified = [t \in Txn |-> FALSE]
    /\ messages = {}
    /\ syncMode = [s \in Server |-> "NONE"]
    /\ syncSource = [s \in Server |-> Nil]
    /\ syncJustified = [s \in Server |-> FALSE]
    /\ pending = [s \in Server |-> <<>>]
    /\ syncCommits = [s \in Server |-> <<>>]
    /\ zkState = [s \in Server |-> "OFF"]
    /\ learnerStep = [s \in Server |-> "none"]
    /\ nlAcks = [s \in Server |-> {}]
    /\ usedTxn = {}
    /\ rollbackAuthorized = [s \in Server |-> FALSE]
    /\ maxCommitted = <<>>
    /\ ackedHist = [s \in Server |-> <<>>]
    /\ treeFloor = [s \in Server |-> NoZxid]

-----------------------------------------------------------------------------
(* Election and discovery *)

(* FastLeaderElection.lookForLeader: logical round and self vote.  Entered  *)
(* from LOOKING only; role exits go through ServerShutdown or Crash.        *)
BeginElection(s) ==
    /\ up[s]
    /\ role[s] = "looking"
    /\ acceptedEpoch[s] < MaxEpoch
    /\ phase' = [phase EXCEPT ![s] = "election"]
    /\ votes' = [votes EXCEPT ![s] = {s}]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    leadersByEpoch, logVars, acked, commitCertified,
                    messages, syncVars, usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

(* FastLeaderElection.totalOrderPredicate (quorum/FastLeaderElection.java:722):*)
(* peer epoch first, then zxid.  The zxid is QuorumPeer.getLastLoggedZxid,   *)
(* i.e. the DataTree's lastProcessedZxid (quorum/QuorumPeer.java:1257-1262), *)
(* not the txn-log tail.  [repair: prior model compared durable logs]       *)
HistoryAtLeast(candidate, voter) ==
    \/ currentEpoch[candidate] > currentEpoch[voter]
    \/ /\ currentEpoch[candidate] = currentEpoch[voter]
       /\ ZxidGE(LastLogged(candidate), LastLogged(voter))

CastVote(voter, candidate) ==
    /\ up[voter] /\ up[candidate]
    /\ role[voter] = "looking"
    /\ HistoryAtLeast(candidate, voter)
    /\ votes' = [votes EXCEPT ![candidate] = @ \cup {voter}]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    leadersByEpoch, logVars, acked, commitCertified,
                    messages, syncVars, usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

(* FLE quorum decision, Leader.lead loadData and getEpochToPropose          *)
(* (quorum/Leader.java:593-603; ZooKeeperServer.java:480-503).  loadData    *)
(* reuses the already-initialized in-memory tree: the leader's history is   *)
(* applied[candidate], not a fresh replay of its txn log.                   *)
WinElection(candidate) ==
    /\ up[candidate]
    /\ role[candidate] = "looking"
    /\ candidate \in votes[candidate]           \* own round started
    /\ Cardinality(votes[candidate]) >= Quorum
    /\ acceptedEpoch[candidate] < MaxEpoch
    /\ LET ep == acceptedEpoch[candidate] + 1 IN
       /\ leadersByEpoch[ep] = {}
       /\ role' = [role EXCEPT ![candidate] = "leading"]
       /\ phase' = [phase EXCEPT ![candidate] = "discovery"]
       /\ leaderOf' = [leaderOf EXCEPT ![candidate] = candidate]
       /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![candidate] = ep]
       /\ leadersByEpoch' = [leadersByEpoch EXCEPT ![ep] = {candidate}]
    /\ proposed' = [proposed EXCEPT ![candidate] = applied[candidate]]
    /\ committed' = [committed EXCEPT ![candidate] = <<>>]
    /\ nlAcks' = [nlAcks EXCEPT ![candidate] = {}]
    /\ ackedHist' = [ackedHist EXCEPT ![candidate] = <<>>]
    /\ votes' = [votes EXCEPT ![candidate] = {}]          \* round consumed
    /\ UNCHANGED <<up, currentEpoch, queued, appended, durable,
                    applied, snapshot, acked, commitCertified, messages,
                    syncMode, syncSource, syncJustified, pending,
                    syncCommits, zkState, learnerStep, usedTxn,
                    maxCommitted, treeFloor>>
    /\ ResetRollback

(* QuorumPeer.run switches a looking peer to FOLLOWING (QuorumPeer.java:1468).*)
FollowLeader(s, l) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "looking"
    /\ role[l] = "leading"
    /\ role' = [role EXCEPT ![s] = "following"]
    /\ phase' = [phase EXCEPT ![s] = "discovery"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = l]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, votes, leadersByEpoch,
                    logVars, acked, commitCertified, messages, syncVars,
                    usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

(* Learner.registerWithLeader persists acceptedEpoch before ACKEPOCH         *)
(* (quorum/Learner.java:483-526).                                            *)
AcceptEpoch(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "discovery"
    /\ leaderOf[s] \in Server
    /\ acceptedEpoch[s] < acceptedEpoch[leaderOf[s]]
    /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![s] = acceptedEpoch[leaderOf[s]]]
    /\ UNCHANGED <<up, role, phase, leaderOf, currentEpoch, votes,
                    leadersByEpoch, logVars, acked, commitCertified,
                    messages, syncVars, usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

(* Leader.waitForEpochAck then setCurrentEpoch (quorum/Leader.java:653-656). *)
FinishDiscovery(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "discovery"
    /\ Cardinality({s \in Server : up[s] /\ acceptedEpoch[s] = acceptedEpoch[l]
                                  /\ (s = l \/ leaderOf[s] = l)}) >= Quorum
    /\ currentEpoch' = [currentEpoch EXCEPT ![l] = acceptedEpoch[l]]
    /\ phase' = [phase EXCEPT ![l] = "sync"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, votes,
                    leadersByEpoch, logVars, acked, commitCertified,
                    messages, syncVars, usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

(* Follower.followLeader sets SYNCHRONIZATION before syncWithLeader        *)
(* (quorum/Follower.java:108-109).                                           *)
EnterSyncPhase(s, l) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "following" /\ leaderOf[s] = l
    /\ phase[s] = "discovery" /\ phase[l] \in {"sync", "broadcast"}
    /\ acceptedEpoch[s] = acceptedEpoch[l]
    /\ phase' = [phase EXCEPT ![s] = "sync"]
    /\ syncSource' = [syncSource EXCEPT ![s] = l]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, logVars, acked, commitCertified,
                    messages, syncMode, syncJustified, pending, syncCommits,
                    zkState, learnerStep, nlAcks, usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

-----------------------------------------------------------------------------
(* Synchronization (Learner.syncWithLeader / LearnerHandler.syncFollower) *)

DiffAllowed(s, l) == IsPrefix(applied[s], SyncCommittedHist(l))
TruncAllowed(s, l) == /\ IsPrefix(SyncCommittedHist(l), applied[s])
                      /\ SyncCommittedHist(l) /= applied[s]

(* LearnerHandler.syncFollower (quorum/LearnerHandler.java:775-933) chooses  *)
(* the mode from the learner's reported zxid (its tree) under the leader's   *)
(* log lock and queues the stream; startForwarding (:920) then forwards       *)
(* outstanding proposals.  The learner consumes the directive and every      *)
(* packet before NEWLEADER (quorum/Learner.java:557-710).  Nothing else at   *)
(* the learner interleaves with this read loop, so the stream is consumed    *)
(* atomically; later forwarded packets arrive through ReceiveProposal/Commit.*)
SyncWithLeader(s, mode) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ learnerStep[s] = "none"
    /\ syncSource[s] = leaderOf[s]
    /\ leaderOf[s] \in Server
    /\ LET l == leaderOf[s]
           lc == SyncCommittedHist(l)
           lp == proposed[l]
           base == applied[s] IN
       /\ up[l] /\ role[l] = "leading" /\ phase[l] \in {"sync", "broadcast"}
       /\ acceptedEpoch[s] = acceptedEpoch[l]
       /\ mode \in SyncModes \ {"NONE"}
       /\ IF mode = "DIFF" THEN DiffAllowed(s, l)
          ELSE IF mode = "TRUNC" THEN TruncAllowed(s, l)
          ELSE ~(DiffAllowed(s, l) \/ TruncAllowed(s, l)) \/ base = <<>>
       /\ syncMode' = [syncMode EXCEPT ![s] = mode]
       /\ syncJustified' = [syncJustified EXCEPT ![s] = TRUE]
       /\ learnerStep' = [learnerStep EXCEPT ![s] = "synced"]
       /\ proposed' = [proposed EXCEPT ![s] = lp]
       /\ CASE mode = "DIFF" ->
               \* Learner.java:561-564 DIFF keeps the tree; writeToTxnLog is
               \* true, so PROPOSAL -> packetsNotCommitted (:621-641) and
               \* COMMIT -> packetsCommitted (:666-667).
               /\ pending' = [pending EXCEPT ![s] = Suffix(lp, Len(base))]
               /\ syncCommits' = [syncCommits EXCEPT ![s] = Suffix(lc, Len(base))]
               /\ committed' = [committed EXCEPT ![s] = base]
               /\ UNCHANGED <<queued, appended, durable, applied, treeFloor>>
               /\ ResetRollback
            [] mode = "TRUNC" ->
               \* Learner.java:587-596 truncateLog then reload
               \* (ZKDatabase.java:599-622).
               LET tlog == TruncateLog(durable[s], LastZ(lc)) IN
               /\ durable' = [durable EXCEPT ![s] = tlog]
               /\ appended' = [appended EXCEPT ![s] = tlog]
               /\ queued' = [queued EXCEPT ![s] = tlog]
               /\ applied' = [applied EXCEPT ![s] = Restore(snapshot[s], tlog)]
               /\ pending' = [pending EXCEPT ![s] = Suffix(lp, Len(lc))]
               /\ syncCommits' = [syncCommits EXCEPT ![s] = <<>>]
               /\ committed' = [committed EXCEPT ![s] = lc]
               /\ treeFloor' = [treeFloor EXCEPT ![s] = LastZ(lc)]  \* Learner.java:597
               /\ rollbackAuthorized' = [x \in Server |-> x = s]
            [] OTHER ->
               \* Learner.java:565-587 SNAP clears and deserializes the
               \* leader tree; the txn log is untouched until NEWLEADER.
               /\ applied' = [applied EXCEPT ![s] = lc]
               /\ pending' = [pending EXCEPT ![s] = Suffix(lp, Len(lc))]
               /\ syncCommits' = [syncCommits EXCEPT ![s] = <<>>]
               /\ committed' = [committed EXCEPT ![s] = lc]
               /\ treeFloor' = [treeFloor EXCEPT ![s] = LastLogged(l)]  \* Learner.java:583
               /\ UNCHANGED <<queued, appended, durable>>
               /\ rollbackAuthorized' = [x \in Server |-> x = s]
    \* A new synchronization supersedes the previous NEWLEADER attestation.
    /\ ackedHist' = [ackedHist EXCEPT ![s] = <<>>]
    /\ UNCHANGED <<serverVars, snapshot, acked, commitCertified, messages,
                    syncSource, zkState, nlAcks, usedTxn, maxCommitted>>

(* NEWLEADER, part 1 (quorum/Learner.java:726-748): optional snapshot for  *)
(* SNAP/TRUNC (snapshotNeeded), then setCurrentEpoch writes the file.       *)
LearnerNewLeaderPersist(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ learnerStep[s] = "synced"
    /\ leaderOf[s] \in Server
    /\ acceptedEpoch[s] = acceptedEpoch[leaderOf[s]]
    /\ snapshot' = IF syncMode[s] /= "DIFF"
                   THEN [snapshot EXCEPT ![s] = applied[s]]   \* :739-741
                   ELSE snapshot
    /\ currentEpoch' = [currentEpoch EXCEPT ![s] = acceptedEpoch[s]]  \* :743
    /\ learnerStep' = [learnerStep EXCEPT ![s] = "epochPersisted"]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, acked, commitCertified, messages,
                    syncMode, syncSource, syncJustified, pending,
                    syncCommits, zkState, nlAcks, usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

\* UPDATE-MAP
\* code: quorum/Learner.java:748-751 (new); ZooKeeperServer.java:673-704
\* update: Update!AffectedActions (LearnerNewLeaderStartup)
(* NEWLEADER, part 2 (new code): setSyncMode(NONE) and                      *)
(* zk.startupWithoutServing() -- processors start, state INITIAL.           *)
LearnerNewLeaderStartup(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ learnerStep[s] = "epochPersisted"
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]            \* Learner.java:750
    /\ zkState' = [zkState EXCEPT ![s] = "INITIAL"]           \* Learner.java:751
    /\ learnerStep' = [learnerStep EXCEPT ![s] = "started"]
    /\ UNCHANGED <<serverVars, logVars, acked, commitCertified, messages,
                    syncSource, syncJustified, pending, syncCommits, nlAcks,
                    usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

\* UPDATE-MAP
\* code: quorum/Learner.java:752-757 (new); FollowerZooKeeperServer.java:82-90
\* update: Update!AffectedActions (LearnerLogPendingOne)
(* NEWLEADER, part 3 (new code): fzk.logRequest for each packetsNotCommitted*)
(* entry.  logRequest only enqueues to SyncRequestProcessor (asynchronous). *)
LearnerLogPendingOne(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ learnerStep[s] = "started"
    /\ pending[s] /= <<>>
    /\ queued' = [queued EXCEPT ![s] = Append(@, Head(pending[s]))]
    /\ pending' = [pending EXCEPT ![s] = Tail(@)]
    /\ UNCHANGED <<serverVars, proposed, appended, durable, committed,
                    applied, snapshot, acked, commitCertified, messages,
                    syncMode, syncSource, syncJustified, syncCommits,
                    zkState, learnerStep, nlAcks, usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

\* UPDATE-MAP
\* code: quorum/Learner.java:757-760 (new); Leader.java:1547-1573
\* update: Update!AffectedActions (LearnerSendNewLeaderAck)
(* NEWLEADER, part 4: packetsNotCommitted.clear() and ACK(newLeaderZxid).   *)
(* The leader's LearnerHandler reads it and Leader.waitForNewLeaderAck adds *)
(* the sid (LearnerHandler.java:611-623).  The ACK does not wait for the    *)
(* SyncRequestProcessor flush.                                             *)
LearnerSendNewLeaderAck(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ learnerStep[s] = "started"
    /\ pending[s] = <<>>
    /\ leaderOf[s] \in Server
    /\ LET l == leaderOf[s] IN
       /\ up[l] /\ role[l] = "leading"
       /\ acceptedEpoch[s] = acceptedEpoch[l]
       /\ nlAcks' = [nlAcks EXCEPT ![l] = @ \cup {s}]
    /\ learnerStep' = [learnerStep EXCEPT ![s] = "acked"]
    \* ghost: the ACK attests every packet received before NEWLEADER
    /\ ackedHist' = [ackedHist EXCEPT ![s] = proposed[s]]
    /\ UNCHANGED <<serverVars, logVars, acked, commitCertified, messages,
                    syncMode, syncSource, syncJustified, pending,
                    syncCommits, zkState, usedTxn, maxCommitted, treeFloor>>
    /\ ResetRollback

(* Leader.lead: waitForNewLeaderAck quorum then startZkServer               *)
(* (quorum/Leader.java:661-688, :1497-1530).  zk.startup() makes the        *)
(* loaded history the leader's committed state (lastCommitted = zxid).      *)
LeaderStartZkServer(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "sync"
    /\ zkState[l] = "OFF"
    /\ Cardinality(nlAcks[l] \cup {l}) >= Quorum
    /\ zkState' = [zkState EXCEPT ![l] = "RUNNING"]
    /\ committed' = [committed EXCEPT ![l] = proposed[l]]
    /\ commitCertified' = [t \in Txn |-> commitCertified[t]
                                         \/ t \in TxnIds(proposed[l])]
    /\ maxCommitted' = GrowGhost(maxCommitted, proposed[l])
    \* Leader.java:1536 setlastProcessedZxid(zk.getZxid()) = (epoch, 0)
    /\ treeFloor' = [treeFloor EXCEPT ![l] = Zx(currentEpoch[l], 0)]
    /\ UNCHANGED <<serverVars, proposed, queued, appended, durable, applied,
                    snapshot, acked, messages, syncMode, syncSource,
                    syncJustified, pending, syncCommits, learnerStep, nlAcks,
                    usedTxn, ackedHist>>
    /\ ResetRollback

(* Leader.lead sets BROADCAST after startZkServer (quorum/Leader.java:712). *)
LeaderEnterBroadcast(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "sync"
    /\ zkState[l] = "RUNNING"
    /\ phase' = [phase EXCEPT ![l] = "broadcast"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, logVars, acked, commitCertified,
                    messages, syncVars, usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

\* UPDATE-MAP
\* code: quorum/Learner.java:711-725, :762-767 (new: startServing replaces startup)
\* update: Update!AffectedActions (LearnerUptodateStartServing)
(* UPTODATE: the LearnerHandler sends it after waitForStartup               *)
(* (LearnerHandler.java:641-648).  The learner leaves the read loop, writes *)
(* the ACK and zk.startServing() sets RUNNING (Learner.java:765-767).       *)
LearnerUptodateStartServing(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ learnerStep[s] = "acked"
    /\ leaderOf[s] \in Server
    /\ LET l == leaderOf[s] IN
       /\ up[l] /\ role[l] = "leading" /\ zkState[l] = "RUNNING"
       /\ acceptedEpoch[s] = acceptedEpoch[l]
    /\ zkState' = [zkState EXCEPT ![s] = "RUNNING"]
    /\ learnerStep' = [learnerStep EXCEPT ![s] = "serving"]
    /\ UNCHANGED <<serverVars, logVars, acked, commitCertified, messages,
                    syncMode, syncSource, syncJustified, pending,
                    syncCommits, nlAcks, usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

\* UPDATE-MAP
\* code: quorum/Learner.java:776-782 (packets buffered after NEWLEADER)
\* update: Update!AffectedActions (LearnerUptodateLogOne)
LearnerUptodateLogOne(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ learnerStep[s] = "serving"
    /\ pending[s] /= <<>>
    /\ queued' = [queued EXCEPT ![s] = Append(@, Head(pending[s]))]
    /\ pending' = [pending EXCEPT ![s] = Tail(@)]
    /\ UNCHANGED <<serverVars, proposed, appended, durable, committed,
                    applied, snapshot, acked, commitCertified, messages,
                    syncMode, syncSource, syncJustified, syncCommits,
                    zkState, learnerStep, nlAcks, usedTxn, maxCommitted,
                    ackedHist, treeFloor>>
    /\ ResetRollback

\* UPDATE-MAP
\* code: quorum/Learner.java:783-785; FollowerZooKeeperServer.java:99-111
\* update: Update!AffectedActions (LearnerUptodateCommitOne)
(* fzk.commit(zxid) for each packetsCommitted entry; the zxid must match the*)
(* pendingTxns head, otherwise the server exits (FollowerZooKeeperServer:104).*)
LearnerUptodateCommitOne(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ learnerStep[s] = "serving"
    /\ pending[s] = <<>> /\ syncCommits[s] /= <<>>
    /\ Len(committed[s]) < Len(proposed[s])
    /\ proposed[s][Len(committed[s]) + 1] = Head(syncCommits[s])
    /\ committed' = [committed EXCEPT ![s] = Append(@, Head(syncCommits[s]))]
    /\ syncCommits' = [syncCommits EXCEPT ![s] = Tail(@)]
    /\ UNCHANGED <<serverVars, proposed, queued, appended, durable, applied,
                    snapshot, acked, commitCertified, messages, syncMode,
                    syncSource, syncJustified, pending, zkState, learnerStep,
                    nlAcks, usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

(* syncWithLeader returns; Follower.followLeader sets BROADCAST              *)
(* (quorum/Follower.java:109-110).                                           *)
LearnerEnterBroadcast(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ learnerStep[s] = "serving"
    /\ pending[s] = <<>> /\ syncCommits[s] = <<>>
    /\ phase' = [phase EXCEPT ![s] = "broadcast"]
    /\ learnerStep' = [learnerStep EXCEPT ![s] = "none"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, logVars, acked, commitCertified,
                    messages, syncMode, syncSource, syncJustified, pending,
                    syncCommits, zkState, nlAcks, usedTxn, maxCommitted,
                    ackedHist, treeFloor>>
    /\ ResetRollback

-----------------------------------------------------------------------------
(* Broadcast pipeline *)

(* ProposalRequestProcessor -> Leader.propose (quorum/Leader.java:1215) then *)
(* local SyncRequestProcessor; requests flow only while RUNNING.            *)
Propose(l, t) ==
    /\ up[l] /\ role[l] = "leading" /\ zkState[l] = "RUNNING"
    /\ t \in Txn \ usedTxn
    /\ LET ent == [id |-> t, epoch |-> currentEpoch[l],
                   ctr |-> NextCtr(proposed[l], currentEpoch[l])] IN
       /\ proposed' = [proposed EXCEPT ![l] = Append(@, ent)]
       /\ queued' = [queued EXCEPT ![l] = Append(@, ent)]
       /\ messages' = messages \cup
             {[kind |-> "proposal", from |-> l, to |-> s, ent |-> ent] :
                 s \in Forwarding(l)}
    /\ usedTxn' = usedTxn \cup {t}
    /\ UNCHANGED <<serverVars, appended, durable, committed, applied,
                    snapshot, acked, commitCertified, syncVars,
                    maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

(* Follower.processPacket PROPOSAL -> fzk.logRequest (quorum/Follower.java:165);*)
(* during sync: packetsNotCommitted.add (quorum/Learner.java:621-641).      *)
ReceiveProposal(m) ==
    /\ m \in messages /\ m.kind = "proposal"
    /\ LET s == m.to IN
       /\ up[s] /\ role[s] = "following" /\ leaderOf[s] = m.from
       /\ acceptedEpoch[s] = m.ent.epoch
       /\ \/ /\ phase[s] = "broadcast"
             /\ proposed' = [proposed EXCEPT ![s] = Append(@, m.ent)]
             /\ queued' = [queued EXCEPT ![s] = Append(@, m.ent)]
             /\ UNCHANGED pending
          \/ /\ phase[s] = "sync" /\ learnerStep[s] \in {"synced", "acked"}
             /\ proposed' = [proposed EXCEPT ![s] = Append(@, m.ent)]
             /\ pending' = [pending EXCEPT ![s] = Append(@, m.ent)]
             /\ UNCHANGED queued
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<serverVars, appended, durable, committed, applied,
                    snapshot, acked, commitCertified, syncMode, syncSource,
                    syncJustified, syncCommits, zkState, learnerStep, nlAcks,
                    usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

(* SyncRequestProcessor.run appends to the txn stream (SyncRequestProcessor.java:182).*)
(* The thread is independent of the role loop and keeps running when a     *)
(* server instance is abandoned without shutdown.                          *)
AppendOne(s) ==
    /\ up[s] /\ Len(appended[s]) < Len(queued[s])
    /\ appended' = [appended EXCEPT ![s] = Append(@, queued[s][Len(appended[s]) + 1])]
    /\ UNCHANGED <<serverVars, proposed, queued, durable, committed, applied,
                    snapshot, acked, commitCertified, messages, syncVars,
                    usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

(* SyncRequestProcessor.flush: ZKDatabase.commit forces the log, then the  *)
(* ACK processor runs (SyncRequestProcessor.java:228-251).  A follower's    *)
(* SendAckRequestProcessor write fails on an abandoned connection.          *)
FsyncOne(s) ==
    /\ up[s] /\ Len(durable[s]) < Len(appended[s])
    /\ LET ent == appended[s][Len(durable[s]) + 1] IN
       /\ durable' = [durable EXCEPT ![s] = Append(@, ent)]
       /\ IF role[s] = "leading" /\ zkState[s] /= "OFF"
          THEN /\ acked' = [acked EXCEPT ![ent.id] = @ \cup {s}]
               /\ messages' = messages
          ELSE IF role[s] = "following" /\ zkState[s] /= "OFF"
                  /\ leaderOf[s] \in Server
               THEN /\ acked' = acked
                    /\ messages' = messages \cup
                         {[kind |-> "ack", from |-> s, to |-> leaderOf[s],
                           ent |-> ent]}
               ELSE UNCHANGED <<acked, messages>>
    /\ UNCHANGED <<serverVars, proposed, queued, appended, committed,
                    applied, snapshot, commitCertified, syncVars, usedTxn,
                    maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

DeliverAck(m) ==
    /\ m \in messages /\ m.kind = "ack" /\ up[m.to]
    /\ acked' = [acked EXCEPT ![m.ent.id] = @ \cup {m.from}]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<serverVars, logVars, commitCertified, syncVars, usedTxn,
                    maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

(* Leader.tryToCommit (quorum/Leader.java:890-963): next outstanding       *)
(* proposal with quorum ACKs; COMMIT is sent to forwarding learners.       *)
Commit(l, t) ==
    /\ up[l] /\ role[l] = "leading" /\ zkState[l] = "RUNNING"
    /\ Len(committed[l]) < Len(proposed[l])
    /\ LET ent == proposed[l][Len(committed[l]) + 1] IN
       /\ ent.id = t
       /\ Cardinality(acked[t]) >= Quorum
       /\ committed' = [committed EXCEPT ![l] = Append(@, ent)]
       /\ commitCertified' = [commitCertified EXCEPT ![t] = TRUE]
       /\ messages' = messages \cup
            {[kind |-> "commit", from |-> l, to |-> s, ent |-> ent] :
                s \in Forwarding(l)}
       /\ maxCommitted' = GrowGhost(maxCommitted, Append(committed[l], ent))
    /\ UNCHANGED <<serverVars, proposed, queued, appended, durable, applied,
                    snapshot, acked, syncVars, usedTxn, ackedHist, treeFloor>>
    /\ ResetRollback

(* Follower COMMIT -> FollowerZooKeeperServer.commit (FollowerZooKeeperServer.java:99-111);*)
(* during sync: packetsCommitted.add when writing to the txn log, else      *)
(* processTxn of the matching packetsNotCommitted head (Learner.java:643-668).*)
ReceiveCommit(m) ==
    /\ m \in messages /\ m.kind = "commit"
    /\ LET s == m.to IN
       /\ up[s] /\ role[s] = "following" /\ leaderOf[s] = m.from
       /\ acceptedEpoch[s] = m.ent.epoch
       /\ CASE phase[s] = "broadcast" ->
               /\ Len(committed[s]) < Len(proposed[s])
               /\ proposed[s][Len(committed[s]) + 1] = m.ent
               /\ committed' = [committed EXCEPT ![s] = Append(@, m.ent)]
               /\ UNCHANGED <<applied, pending, syncCommits>>
            [] phase[s] = "sync" /\ learnerStep[s] \in {"synced", "acked"}
               /\ (syncMode[s] = "DIFF" \/ learnerStep[s] = "acked") ->
               /\ LET k == Len(committed[s]) + Len(syncCommits[s]) + 1 IN
                  /\ k <= Len(proposed[s])
                  /\ proposed[s][k] = m.ent
               /\ syncCommits' = [syncCommits EXCEPT ![s] = Append(@, m.ent)]
               /\ UNCHANGED <<committed, applied, pending>>
            [] phase[s] = "sync" /\ learnerStep[s] = "synced"
               /\ syncMode[s] /= "DIFF" ->
               /\ pending[s] /= <<>> /\ Head(pending[s]) = m.ent
               /\ applied' = [applied EXCEPT ![s] = Append(@, m.ent)]
               /\ committed' = [committed EXCEPT ![s] = Append(@, m.ent)]
               /\ pending' = [pending EXCEPT ![s] = Tail(@)]
               /\ UNCHANGED syncCommits
            [] OTHER -> FALSE
    /\ commitCertified' = [commitCertified EXCEPT ![m.ent.id] = TRUE]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<serverVars, proposed, queued, appended, durable, snapshot,
                    acked, syncMode, syncSource, syncJustified, zkState,
                    learnerStep, nlAcks, usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

(* CommitProcessor -> FinalRequestProcessor -> ZooKeeperServer.processTxn   *)
(* (ZooKeeperServer.java:1785-1800): applies the next certified commit.     *)
ApplyOne(s) ==
    /\ up[s] /\ zkState[s] = "RUNNING"
    /\ IsPrefix(applied[s], committed[s])
    /\ Len(applied[s]) < Len(committed[s])
    /\ LET ent == committed[s][Len(applied[s]) + 1] IN
       /\ commitCertified[ent.id]
       /\ applied' = [applied EXCEPT ![s] = Append(@, ent)]
    /\ UNCHANGED <<serverVars, proposed, queued, appended, durable,
                    committed, snapshot, acked, commitCertified, messages,
                    syncVars, usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

(* SyncRequestProcessor periodic snapshot of the DataTree                   *)
(* (SyncRequestProcessor.java:183-200, ZooKeeperServer.takeSnapshot:514).   *)
TakeSnapshot(s) ==
    /\ up[s] /\ zkState[s] = "RUNNING" /\ snapshot[s] /= applied[s]
    /\ snapshot' = [snapshot EXCEPT ![s] = applied[s]]
    /\ UNCHANGED <<serverVars, proposed, queued, appended, durable,
                    committed, applied, acked, commitCertified, messages,
                    syncVars, usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

-----------------------------------------------------------------------------
(* Role exit, crash and restart *)

\* UPDATE-MAP
\* code: quorum/QuorumPeer.java:1468-1494; quorum/Learner.java:850-864;
\*       quorum/LearnerZooKeeperServer.java:155-173; ZooKeeperServer.java:784-850
\* update: Update!InteractionActions (ServerShutdown)
(* A role loop exits (socket timeout, leader loss, lost quorum) and the     *)
(* server instance is shut down.  Learner/ZooKeeperServer.shutdown return   *)
(* immediately unless the state is RUNNING (canShutdown); only then are the *)
(* processors stopped, the tree fast-forwarded from the log and the        *)
(* follower SyncRequestProcessor drained.  Leader: ProposalRequestProcessor*)
(* drains its sync processor before the fast-forward; follower: the tree is*)
(* fast-forwarded before syncProcessor.shutdown.  When the instance is not *)
(* RUNNING (new code: between NEWLEADER and UPTODATE) its sync processor   *)
(* keeps flushing in the background (AppendOne/FsyncOne).                   *)
ServerShutdown(s) ==
    /\ up[s] /\ role[s] \in {"leading", "following"}
    /\ LET running == zkState[s] = "RUNNING" IN
       /\ applied' = [applied EXCEPT ![s] =
             IF ~running THEN @
             ELSE IF role[s] = "leading" THEN FastForward(@, LastLogged(s), queued[s])
             ELSE FastForward(@, LastLogged(s), durable[s])]
       /\ durable' = [durable EXCEPT ![s] = IF running THEN queued[s] ELSE @]
       /\ appended' = [appended EXCEPT ![s] = IF running THEN queued[s] ELSE @]
    /\ role' = [role EXCEPT ![s] = "looking"]
    /\ phase' = [phase EXCEPT ![s] = "election"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = Nil]
    /\ proposed' = [proposed EXCEPT ![s] = <<>>]
    /\ committed' = [committed EXCEPT ![s] = <<>>]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ syncSource' = [syncSource EXCEPT ![s] = Nil]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = FALSE]
    /\ pending' = [pending EXCEPT ![s] = <<>>]
    /\ syncCommits' = [syncCommits EXCEPT ![s] = <<>>]
    /\ zkState' = [zkState EXCEPT ![s] = "OFF"]
    /\ learnerStep' = [learnerStep EXCEPT ![s] = "none"]
    /\ nlAcks' = [nlAcks EXCEPT ![s] = {}]
    /\ votes' = ForgetVotes(s)
    /\ rollbackAuthorized' = [x \in Server |-> x = s]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, leadersByEpoch,
                    queued, snapshot, acked, commitCertified, messages,
                    usedTxn, maxCommitted, ackedHist, treeFloor>>

(* Process crash: memory, queues and unflushed appends are lost.            *)
Crash(s) ==
    /\ up[s]
    /\ up' = [up EXCEPT ![s] = FALSE]
    /\ role' = [role EXCEPT ![s] = "looking"]
    /\ phase' = [phase EXCEPT ![s] = "offline"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = Nil]
    /\ proposed' = [proposed EXCEPT ![s] = <<>>]
    /\ queued' = [queued EXCEPT ![s] = durable[s]]
    /\ appended' = [appended EXCEPT ![s] = durable[s]]
    /\ committed' = [committed EXCEPT ![s] = <<>>]
    /\ applied' = [applied EXCEPT ![s] = <<>>]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ syncSource' = [syncSource EXCEPT ![s] = Nil]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = FALSE]
    /\ pending' = [pending EXCEPT ![s] = <<>>]
    /\ syncCommits' = [syncCommits EXCEPT ![s] = <<>>]
    /\ zkState' = [zkState EXCEPT ![s] = "OFF"]
    /\ learnerStep' = [learnerStep EXCEPT ![s] = "none"]
    /\ nlAcks' = [nlAcks EXCEPT ![s] = {}]
    /\ treeFloor' = [treeFloor EXCEPT ![s] = NoZxid]
    /\ votes' = ForgetVotes(s)
    /\ rollbackAuthorized' = [x \in Server |-> x = s]
    /\ UNCHANGED <<acceptedEpoch, currentEpoch, leadersByEpoch,
                    durable, snapshot, acked, commitCertified, messages,
                    usedTxn, maxCommitted, ackedHist>>

(* QuorumPeer.start -> loadDataBase -> FileTxnSnapLog.restore              *)
(* (quorum/QuorumPeer.java:1088-1103; persistence/FileTxnSnapLog.java:243). *)
Restart(s) ==
    /\ ~up[s]
    /\ up' = [up EXCEPT ![s] = TRUE]
    /\ phase' = [phase EXCEPT ![s] = "election"]
    /\ applied' = [applied EXCEPT ![s] = Restore(snapshot[s], durable[s])]
    /\ UNCHANGED <<role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, snapshot, acked, commitCertified, messages,
                    syncVars, usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

DropMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<serverVars, logVars, acked, commitCertified, syncVars,
                    usedTxn, maxCommitted, ackedHist, treeFloor>>
    /\ ResetRollback

-----------------------------------------------------------------------------
Next ==
    \/ \E s \in Server : BeginElection(s)
    \/ \E voter, candidate \in Server : CastVote(voter, candidate)
    \/ \E s \in Server : WinElection(s)
    \/ \E s, l \in Server : FollowLeader(s, l)
    \/ \E s \in Server : AcceptEpoch(s)
    \/ \E l \in Server : FinishDiscovery(l)
    \/ \E s, l \in Server : EnterSyncPhase(s, l)
    \/ \E s \in Server, mode \in SyncModes \ {"NONE"} : SyncWithLeader(s, mode)
    \/ \E s \in Server : LearnerNewLeaderPersist(s)
    \/ \E s \in Server : LearnerNewLeaderStartup(s)
    \/ \E s \in Server : LearnerLogPendingOne(s)
    \/ \E s \in Server : LearnerSendNewLeaderAck(s)
    \/ \E l \in Server : LeaderStartZkServer(l)
    \/ \E l \in Server : LeaderEnterBroadcast(l)
    \/ \E s \in Server : LearnerUptodateStartServing(s)
    \/ \E s \in Server : LearnerUptodateLogOne(s)
    \/ \E s \in Server : LearnerUptodateCommitOne(s)
    \/ \E s \in Server : LearnerEnterBroadcast(s)
    \/ \E l \in Server, t \in Txn : Propose(l, t)
    \/ \E m \in messages : ReceiveProposal(m)
    \/ \E s \in Server : AppendOne(s)
    \/ \E s \in Server : FsyncOne(s)
    \/ \E m \in messages : DeliverAck(m)
    \/ \E l \in Server, t \in Txn : Commit(l, t)
    \/ \E m \in messages : ReceiveCommit(m)
    \/ \E s \in Server : ApplyOne(s)
    \/ \E s \in Server : TakeSnapshot(s)
    \/ \E s \in Server : ServerShutdown(s)
    \/ \E s \in Server : Crash(s)
    \/ \E s \in Server : Restart(s)
    \/ \E m \in messages : DropMessage(m)

Spec == Init /\ [][Next]_allVars

-----------------------------------------------------------------------------
(* Properties *)

TypeOK ==
    /\ up \in [Server -> BOOLEAN]
    /\ role \in [Server -> Role]
    /\ phase \in [Server -> Phase]
    /\ leaderOf \in [Server -> (Server \cup {Nil})]
    /\ acceptedEpoch \in [Server -> Epoch]
    /\ currentEpoch \in [Server -> Epoch]
    /\ votes \in [Server -> SUBSET Server]
    /\ leadersByEpoch \in [Epoch -> SUBSET Server]
    /\ \A s \in Server :
         \A h \in {proposed[s], queued[s], appended[s], durable[s],
                   committed[s], applied[s], snapshot[s], pending[s],
                   syncCommits[s]} : h \in Seq(Entry)
    /\ acked \in [Txn -> SUBSET Server]
    /\ commitCertified \in [Txn -> BOOLEAN]
    /\ messages \subseteq Message
    /\ syncMode \in [Server -> SyncModes]
    /\ syncSource \in [Server -> (Server \cup {Nil})]
    /\ syncJustified \in [Server -> BOOLEAN]
    /\ zkState \in [Server -> ZkStates]
    /\ learnerStep \in [Server -> LearnerSteps]
    /\ nlAcks \in [Server -> SUBSET Server]
    /\ usedTxn \subseteq Txn
    /\ rollbackAuthorized \in [Server -> BOOLEAN]
    /\ maxCommitted \in Seq(Entry)
    /\ ackedHist \in [Server -> Seq(Entry)]
    /\ treeFloor \in [Server -> [epoch : Epoch, ctr : Nat]]

ElectionSafety == \A e \in Epoch : Cardinality(leadersByEpoch[e]) <= 1

\* [refined, Case A] A peer is LEADING before Leader.getEpochToPropose
\* persists its new epoch (QuorumPeer.java:1481 vs Leader.java:602); only
\* leaders bound to their accepted epoch (leadersByEpoch) are counted.
OneActiveLeaderPerEpoch ==
    \A e \in Epoch :
        Cardinality({s \in Server : up[s] /\ role[s] = "leading"
                                    /\ acceptedEpoch[s] = e
                                    /\ s \in leadersByEpoch[e]}) <= 1

\* Commit knowledge of active role instances agrees on common prefixes.
CommittedHistoriesPrefix ==
    \A a, b \in Server : Comparable(committed[a], committed[b])

\* [revised repair] Restart replays every logged txn into the tree
\* (FileTxnSnapLog.restore), so only a serving instance promises that its
\* tree is a certified commit prefix.
ServingApplyRequiresCommitCertificate ==
    \A s \in Server :
        (up[s] /\ zkState[s] = "RUNNING") =>
          /\ IsPrefix(applied[s], committed[s])
          /\ \A k \in 1..Len(applied[s]) : commitCertified[applied[s][k].id]

PipelinePrefix ==
    \A s \in Server :
        /\ IsPrefix(durable[s], appended[s])
        /\ IsPrefix(appended[s], queued[s])
        /\ role[s] \in {"leading", "following"} =>
              IsPrefix(committed[s], proposed[s])

EpochHistoryConsistency ==
    /\ \A s \in Server : currentEpoch[s] <= acceptedEpoch[s]
    /\ \A s \in Server : LastEpoch(durable[s]) <= acceptedEpoch[s]

SyncCompletionJustified ==
    \A s \in Server :
        (role[s] = "following" /\ phase[s] = "broadcast") =>
          /\ syncJustified[s]
          /\ leaderOf[s] \in Server
          /\ currentEpoch[s] = acceptedEpoch[s]
          /\ zkState[s] = "RUNNING"

NoIllegalRollback ==
    \A s \in Server :
       /\ (Len(durable'[s]) >= Len(durable[s]) \/ rollbackAuthorized'[s])
       /\ (Len(committed'[s]) >= Len(committed[s]) \/ rollbackAuthorized'[s])
       /\ (Len(applied'[s]) >= Len(applied[s]) \/ rollbackAuthorized'[s])

HistoryPositionsMonotonicExceptRecovery == [][NoIllegalRollback]_allVars

Safety == TypeOK /\ ElectionSafety /\ OneActiveLeaderPerEpoch /\
          CommittedHistoriesPrefix /\ ServingApplyRequiresCommitCertificate /\
          PipelinePrefix /\ EpochHistoryConsistency /\ SyncCompletionJustified

ModelSymmetry == Permutations(Server)

=============================================================================
