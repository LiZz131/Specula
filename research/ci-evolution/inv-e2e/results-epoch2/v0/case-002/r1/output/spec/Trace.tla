------------------------------ MODULE Trace ------------------------------
(***************************************************************************)
(* Category A linear trace validation for the updated reference.           *)
(* Update-window learner events (NEWLEADER handling, UPTODATE handling,    *)
(* shutdown of a not-yet-serving instance, leader establishment, pipeline  *)
(* steps) replay through the base actions themselves; the remaining        *)
(* election/registration events are tightly-gated observation steps whose  *)
(* fields are compared with the model.  Every captured field is consumed:  *)
(* see ValidateCommonPostState, the per-event checks and                    *)
(* instrumentation-spec.md.                                                 *)
(***************************************************************************)
EXTENDS base, Json, IOUtils, Sequences, TLC

JsonFile == IF "JSON" \in DOMAIN IOEnv
            THEN IOEnv.JSON
            ELSE "../traces/follower-diff.ndjson"

TraceLog == TLCEval(
    SelectSeq(ndJsonDeserialize(JsonFile),
              LAMBDA x : "tag" \in DOMAIN x /\ x.tag = "trace"))

ASSUME Len(TraceLog) > 0

TraceScenario == TraceLog[1].scenario
Fixture == TraceScenario \in {"follower-snap", "follower-diff"}

\* Unique txn identity per zxid (counters restart in every epoch).
TxnIdOf(ep, ctr) == ep * 100000 + ctr
TraceTxn == {TxnIdOf(TraceLog[k].event.txnEpoch, TraceLog[k].event.txnCounter) :
               k \in {j \in 1..Len(TraceLog) : TraceLog[j].event.txnCounter > 0}}
            \cup {TxnIdOf(1, 1), TxnIdOf(1, 2), TxnIdOf(1, 1000)}
TraceMaxEpoch == LET eps == {TraceLog[k].event.txnEpoch : k \in 1..Len(TraceLog)}
                            \cup {TraceLog[k].event.state.acceptedEpoch : k \in 1..Len(TraceLog)}
                 IN CHOOSE m \in eps : \A x \in eps : x <= m

VARIABLE l
traceVars == <<l>>
logline == TraceLog[l]
ev == logline.event
EventName == ev.name
Node == ev.node
TxnEp == ev.txnEpoch
TxnCtr == ev.txnCounter
EvZ == Zx(TxnEp, TxnCtr)
TxnEntry == [id |-> TxnIdOf(TxnEp, TxnCtr), epoch |-> TxnEp, ctr |-> TxnCtr]
Aux == ev.aux
LogZ == Zx(Aux.logEpoch, Aux.logCounter)
EvRole == ev.state.role
EvPhase == ev.state.phase

EventNames == {
    "DatabaseLoaded", "ElectionWon", "PeerRoleChanged", "PhaseChanged",
    "AcceptedEpochPersisted", "CurrentEpochPersisted", "FollowerRegistered",
    "SyncModeChanged", "SyncSelected", "SnapshotInstalled",
    "SyncProposalBuffered", "SyncCommitBuffered", "SyncCommitApplied",
    "ProposalQueued", "NewLeaderAckSent", "UptodateReceived",
    "ZkServerState", "BroadcastReady", "CommitDelivered",
    "TxnAppended", "TxnDurable", "TxnApplied",
    "ZkShutdownSkipped", "ZkShutdownStarted", "ZkTreeFastForwarded",
    "ZkSyncDrained", "NewLeaderAckCounted", "NewLeaderAckRejected",
    "NewLeaderQuorum"}

TraceInputOK ==
    \A k \in 1..Len(TraceLog) :
       LET rec == TraceLog[k] IN
       /\ rec.scenario = TraceScenario
       /\ rec.seq = k
       /\ rec.event.name \in EventNames
       /\ rec.event.node \in Server
       /\ {"acceptedEpoch", "currentEpoch", "role", "phase", "syncMode"}
             \subseteq DOMAIN rec.event.state
       /\ {"zkState", "pending", "committed", "peer", "logEpoch", "logCounter"}
             \subseteq DOMAIN rec.event.aux
       /\ rec.event.state.syncMode \in SyncModes
ASSUME TraceInputOK

-----------------------------------------------------------------------------
(* Mappings *)

FixFollower == "s0"
FixLeader == "s1"

TraceRole(r) ==
    CASE r = "looking" -> IF Fixture THEN "following" ELSE "looking"
      [] r = "following" -> "following"
      [] r = "leading" -> "leading"
      [] OTHER -> "unknown"

TracePhase(p) ==
    CASE p = "discovery" -> "discovery"
      [] p = "synchronization" -> "sync"
      [] p = "broadcast" -> "broadcast"
      [] p = "election" -> "election"
      [] OTHER -> "unknown"

HasEntry(h, e) == \E k \in 1..Len(h) : h[k] = e
IdxOf(h, e) == CHOOSE k \in 1..Len(h) : h[k] = e
PrefixThrough(h, e) == SubSeq(h, 1, IdxOf(h, e))
Last(h) == h[Len(h)]

LeadingSet == {s \in Server : up[s] /\ role[s] = "leading"}
\* Leader resolution for a follower whose FLE result preceded the leader's
\* own role event; ep restricts to the leader of the follower's epoch.
ResolveLeader(n, ep) ==
    IF leaderOf[n] \in Server THEN leaderOf[n]
    ELSE LET c == {x \in LeadingSet : ep < 0 \/ acceptedEpoch[x] = ep} IN
         IF Cardinality(c) = 1 THEN CHOOSE x \in c : TRUE ELSE Nil

\* Disk content observed by a probe that reports the txn-log tail: a prefix
\* of the appended stream at least as long as the fsynced log.
LogMatches(n, z) ==
    \/ z.epoch < 0
    \/ /\ z.ctr <= 0 /\ Len(durable[n]) = 0
    \/ \E k \in Len(durable[n])..Len(appended[n]) :
          k > 0 /\ ZxOf(appended[n][k]) = z

\* DataTree position in the next state (avoid priming the trace cursor).
LastLoggedNext(n) == MaxZ(treeFloor'[n], LastZ(applied'[n]))

ZkMap(z) == CASE z = "RUNNING" -> "RUNNING"
              [] z = "INITIAL" -> "INITIAL"
              [] OTHER -> "OFF"

-----------------------------------------------------------------------------
(* Post-state validation common to every event with peer-level fields.     *)
ValidateCommonPostState ==
    LET st == ev.state IN
    /\ (st.acceptedEpoch >= 0) => acceptedEpoch'[Node] = st.acceptedEpoch
    /\ (st.currentEpoch >= 0) => currentEpoch'[Node] = st.currentEpoch
    /\ (TraceRole(st.role) /= "unknown") => role'[Node] = TraceRole(st.role)
    /\ (TracePhase(st.phase) /= "unknown") => phase'[Node] = TracePhase(st.phase)
    /\ (st.role /= "unknown") => syncMode'[Node] = st.syncMode

\* Role/phase of ZkServerState(SHUTDOWN/ERROR) are QuorumPeer fields read
\* inside ZooKeeperServer.shutdown before the peer loop leaves its role; the
\* model's ServerShutdown is atomic, so only epochs are compared there.
ValidateShutdownStatePost ==
    LET st == ev.state IN
    /\ (st.acceptedEpoch >= 0) => acceptedEpoch'[Node] = st.acceptedEpoch
    /\ (st.currentEpoch >= 0) => currentEpoch'[Node] = st.currentEpoch

-----------------------------------------------------------------------------
(* Observation steps for unchanged election/registration events *)

\* QuorumPeer.start -> loadDataBase after a peer (re)start (Crash;Restart).
DatabaseLoadedStep ==
    /\ EventName = "DatabaseLoaded"
    /\ \E k \in Len(durable[Node])..Len(appended[Node]) :
         LET disk == SubSeq(appended[Node], 1, k) IN
         \* on-disk log tail reported at load time (-1 = no log file)
         /\ IF Aux.logEpoch < 0 THEN disk = <<>> ELSE LastZ(disk) = LogZ
         /\ durable' = [durable EXCEPT ![Node] = disk]
         /\ appended' = [appended EXCEPT ![Node] = disk]
         /\ queued' = [queued EXCEPT ![Node] = disk]
         /\ applied' = [applied EXCEPT ![Node] = Restore(snapshot[Node], disk)]
    /\ up' = [up EXCEPT ![Node] = TRUE]
    /\ role' = [role EXCEPT ![Node] = "looking"]
    /\ phase' = [phase EXCEPT ![Node] = "election"]
    /\ leaderOf' = [leaderOf EXCEPT ![Node] = Nil]
    /\ proposed' = [proposed EXCEPT ![Node] = <<>>]
    /\ committed' = [committed EXCEPT ![Node] = <<>>]
    /\ syncMode' = [syncMode EXCEPT ![Node] = "NONE"]
    /\ syncSource' = [syncSource EXCEPT ![Node] = Nil]
    /\ syncJustified' = [syncJustified EXCEPT ![Node] = FALSE]
    /\ pending' = [pending EXCEPT ![Node] = <<>>]
    /\ syncCommits' = [syncCommits EXCEPT ![Node] = <<>>]
    /\ zkState' = [zkState EXCEPT ![Node] = "OFF"]
    /\ learnerStep' = [learnerStep EXCEPT ![Node] = "none"]
    /\ nlAcks' = [nlAcks EXCEPT ![Node] = {}]
    /\ treeFloor' = [treeFloor EXCEPT ![Node] = NoZxid]
    /\ rollbackAuthorized' = [x \in Server |-> x = Node]
    /\ UNCHANGED <<acceptedEpoch, currentEpoch, votes, leadersByEpoch,
                    snapshot, acked, commitCertified, messages, usedTxn,
                    maxCommitted, ackedHist>>
    /\ LastLoggedNext(Node) = EvZ

\* setPeerState(FOLLOWING/LEADING/LOOKING) (QuorumPeer.java:851-864).
PeerRoleStep ==
    /\ EventName \in {"PeerRoleChanged", "ElectionWon"}
    /\ LET r == TraceRole(EvRole) IN
       \/ /\ r = role[Node]                      \* already reflected
          /\ UNCHANGED allVars
       \/ /\ r = "following" /\ role[Node] = "looking" /\ ~Fixture
          /\ role' = [role EXCEPT ![Node] = "following"]
          /\ leaderOf' = [leaderOf EXCEPT ![Node] = Nil]
          /\ UNCHANGED <<up, phase, acceptedEpoch, currentEpoch, votes,
                          leadersByEpoch, logVars, acked, commitCertified,
                          messages, syncVars, usedTxn, rollbackAuthorized,
                          maxCommitted, ackedHist, treeFloor>>
       \/ /\ r = "leading" /\ role[Node] = "looking" /\ ~Fixture
          \* WinElection effects (Leader.lead loadData reuses the tree)
          /\ role' = [role EXCEPT ![Node] = "leading"]
          /\ leaderOf' = [leaderOf EXCEPT ![Node] = Node]
          /\ proposed' = [proposed EXCEPT ![Node] = applied[Node]]
          /\ committed' = [committed EXCEPT ![Node] = <<>>]
          /\ nlAcks' = [nlAcks EXCEPT ![Node] = {}]
          /\ ackedHist' = [ackedHist EXCEPT ![Node] = <<>>]
          /\ UNCHANGED <<up, phase, acceptedEpoch, currentEpoch, votes,
                          leadersByEpoch, queued, appended, durable, applied,
                          snapshot, acked, commitCertified, messages,
                          syncMode, syncSource, syncJustified, pending,
                          syncCommits, zkState, learnerStep, usedTxn,
                          rollbackAuthorized, maxCommitted, treeFloor>>
    \* zxid: getLastLoggedZxid() = tree for PeerRoleChanged; FLE vote zxid
    \* for ElectionWon (the elected leader's, never below the voter's own).
    /\ IF EventName = "PeerRoleChanged" \/ TraceRole(EvRole) = "leading"
       THEN LastLoggedNext(Node) = EvZ
       ELSE ZxidGE(EvZ, LastLoggedNext(Node))

PhaseStep ==
    /\ EventName = "PhaseChanged"
    /\ LET p == TracePhase(EvPhase) IN
       \/ /\ p = phase[Node]
          /\ UNCHANGED allVars
       \/ /\ p = "election" /\ role[Node] = "looking"
          /\ phase' = [phase EXCEPT ![Node] = "election"]
          /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                          votes, leadersByEpoch, logVars, acked,
                          commitCertified, messages, syncVars, usedTxn,
                          rollbackAuthorized, maxCommitted, ackedHist, treeFloor>>
       \/ /\ p = "discovery" /\ role[Node] \in {"leading", "following"}
          /\ phase' = [phase EXCEPT ![Node] = "discovery"]
          /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                          votes, leadersByEpoch, logVars, acked,
                          commitCertified, messages, syncVars, usedTxn,
                          rollbackAuthorized, maxCommitted, ackedHist, treeFloor>>
       \/ /\ p = "sync" /\ role[Node] = "leading" /\ phase[Node] = "discovery"
          /\ currentEpoch[Node] = acceptedEpoch[Node]       \* FinishDiscovery
          /\ phase' = [phase EXCEPT ![Node] = "sync"]
          /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                          votes, leadersByEpoch, logVars, acked,
                          commitCertified, messages, syncVars, usedTxn,
                          rollbackAuthorized, maxCommitted, ackedHist, treeFloor>>
       \/ /\ p = "sync" /\ role[Node] = "following"
          /\ phase[Node] = "discovery"
          /\ LET ld == ResolveLeader(Node, acceptedEpoch[Node]) IN
             /\ ld \in Server
             /\ acceptedEpoch[Node] = acceptedEpoch[ld]     \* EnterSyncPhase
             /\ leaderOf' = [leaderOf EXCEPT ![Node] = ld]
             /\ syncSource' = [syncSource EXCEPT ![Node] = ld]
          /\ phase' = [phase EXCEPT ![Node] = "sync"]
          /\ UNCHANGED <<up, role, acceptedEpoch, currentEpoch, votes,
                          leadersByEpoch, logVars, acked, commitCertified,
                          messages, syncMode, syncJustified, pending,
                          syncCommits, zkState, learnerStep, nlAcks, usedTxn,
                          rollbackAuthorized, maxCommitted, ackedHist, treeFloor>>
       \/ /\ p = "broadcast" /\ role[Node] = "leading"
          /\ LeaderEnterBroadcast(Node)
          /\ UNCHANGED treeFloor
       \/ /\ p = "broadcast" /\ role[Node] = "following"
          /\ LearnerEnterBroadcast(Node)
    /\ LastLoggedNext(Node) = EvZ

AcceptedEpochStep ==
    /\ EventName = "AcceptedEpochPersisted"
    /\ TxnEp >= acceptedEpoch[Node]
    /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![Node] = TxnEp]
    /\ leadersByEpoch' =
         IF role[Node] = "leading"
         THEN [leadersByEpoch EXCEPT ![TxnEp] = @ \cup {Node}]
         ELSE leadersByEpoch
    /\ leaderOf' =
         IF role[Node] = "following"
         THEN [leaderOf EXCEPT ![Node] = ResolveLeader(Node, TxnEp)]
         ELSE leaderOf
    /\ (role[Node] = "following" /\ ~Fixture) => leaderOf'[Node] \in Server
    /\ UNCHANGED <<up, role, phase, currentEpoch, votes, logVars, acked,
                    commitCertified, messages, syncVars, usedTxn,
                    rollbackAuthorized, maxCommitted, ackedHist, treeFloor>>

CurrentEpochStep ==
    /\ EventName = "CurrentEpochPersisted"
    /\ \/ /\ role[Node] = "following" /\ learnerStep[Node] = "synced"
          /\ LearnerNewLeaderPersist(Node)                  \* NEWLEADER part 1
       \/ /\ role[Node] = "leading" /\ phase[Node] = "discovery"
          /\ TxnEp = acceptedEpoch[Node]                    \* Leader.java:654
          /\ currentEpoch' = [currentEpoch EXCEPT ![Node] = TxnEp]
          /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, votes,
                          leadersByEpoch, logVars, acked, commitCertified,
                          messages, syncVars, usedTxn, rollbackAuthorized,
                          maxCommitted, ackedHist, treeFloor>>
    /\ currentEpoch'[Node] = TxnEp

FollowerRegisteredStep ==
    /\ EventName = "FollowerRegistered"
    /\ role[Node] = "following"
    /\ LastLogged(Node) = EvZ          \* FOLLOWERINFO/ACKEPOCH zxid = tree
    /\ UNCHANGED allVars

SyncModeStep ==
    /\ EventName = "SyncModeChanged"
    /\ \/ /\ ev.state.syncMode /= "NONE"
          /\ role[Node] = "following" /\ phase[Node] = "sync"
          /\ learnerStep[Node] = "none"
          /\ syncMode' = [syncMode EXCEPT ![Node] = ev.state.syncMode]
          /\ UNCHANGED <<serverVars, logVars, acked, commitCertified, messages,
                          syncSource, syncJustified, pending, syncCommits,
                          zkState, learnerStep, nlAcks, usedTxn,
                          rollbackAuthorized, maxCommitted, ackedHist, treeFloor>>
       \/ /\ ev.state.syncMode = "NONE" /\ learnerStep[Node] = "epochPersisted"
          /\ LearnerNewLeaderStartup(Node)                 \* NEWLEADER part 2
    /\ LastLoggedNext(Node) = EvZ

\* LearnerHandler.syncFollower directive consumed by the learner
\* (Learner.java:557-604): mode legality and directive zxid are checked
\* against the leader's model state (fixture leaders are scripted).
SyncSelectedStep ==
    /\ EventName = "SyncSelected"
    /\ role[Node] = "following" /\ phase[Node] = "sync"
    /\ learnerStep[Node] = "none"
    /\ leaderOf[Node] \in Server
    /\ LET ld == leaderOf[Node]
           mode == syncMode[Node]
           lc == SyncCommittedHist(ld) IN
       /\ up[ld] /\ role[ld] = "leading"
       /\ acceptedEpoch[Node] = acceptedEpoch[ld]
       /\ ~Fixture =>
            CASE mode = "DIFF" -> /\ DiffAllowed(Node, ld)
                                  /\ EvZ \in {LastZ(lc), LastLogged(Node)}
              [] mode = "TRUNC" -> /\ TruncAllowed(Node, ld) /\ EvZ = LastZ(lc)
              [] mode = "SNAP" -> EvZ = LastLogged(ld)
              [] OTHER -> FALSE
       /\ syncSource' = [syncSource EXCEPT ![Node] = ld]
       /\ syncJustified' = [syncJustified EXCEPT ![Node] = TRUE]
       /\ learnerStep' = [learnerStep EXCEPT ![Node] = "synced"]
       /\ pending' = [pending EXCEPT ![Node] = <<>>]
       /\ syncCommits' = [syncCommits EXCEPT ![Node] = <<>>]
       /\ ackedHist' = [ackedHist EXCEPT ![Node] = <<>>]
       /\ IF mode = "TRUNC"
          THEN LET tlog == TruncateLog(durable[Node], EvZ) IN
               /\ durable' = [durable EXCEPT ![Node] = tlog]
               /\ appended' = [appended EXCEPT ![Node] = tlog]
               /\ queued' = [queued EXCEPT ![Node] = tlog]
               /\ applied' = [applied EXCEPT ![Node] = Restore(snapshot[Node], tlog)]
               /\ proposed' = [proposed EXCEPT ![Node] = Restore(snapshot[Node], tlog)]
               /\ committed' = [committed EXCEPT ![Node] = Restore(snapshot[Node], tlog)]
               /\ treeFloor' = [treeFloor EXCEPT ![Node] = EvZ]
               /\ rollbackAuthorized' = [x \in Server |-> x = Node]
          ELSE IF mode = "SNAP"
          \* history replaced at SnapshotInstalled (deserializeSnapshot)
          THEN /\ proposed' = [proposed EXCEPT ![Node] = <<>>]
               /\ committed' = [committed EXCEPT ![Node] = <<>>]
               /\ rollbackAuthorized' = [x \in Server |-> x = Node]
               /\ UNCHANGED <<queued, appended, durable, applied, treeFloor>>
          ELSE /\ proposed' = [proposed EXCEPT ![Node] = applied[Node]]
               /\ committed' = [committed EXCEPT ![Node] = applied[Node]]
               /\ UNCHANGED <<queued, appended, durable, applied, treeFloor,
                               rollbackAuthorized>>
    /\ UNCHANGED <<serverVars, snapshot, acked, commitCertified, messages,
                    syncMode, zkState, nlAcks, usedTxn, maxCommitted>>

\* SNAP: deserializeSnapshot + setlastProcessedZxid (Learner.java:565-584).
SnapshotInstalledStep ==
    /\ EventName = "SnapshotInstalled"
    /\ learnerStep[Node] = "synced" /\ syncMode[Node] = "SNAP"
    /\ LET ld == leaderOf[Node]
           img == IF TxnCtr = 0 THEN applied[ld]
                  ELSE IF HasEntry(proposed[ld], TxnEntry)
                       THEN PrefixThrough(proposed[ld], TxnEntry)
                       ELSE <<>> IN
       /\ TxnCtr = 0 \/ HasEntry(proposed[ld], TxnEntry)
       /\ applied' = [applied EXCEPT ![Node] = img]
       /\ committed' = [committed EXCEPT ![Node] = img]
       /\ proposed' = [proposed EXCEPT ![Node] = img]
    /\ treeFloor' = [treeFloor EXCEPT ![Node] = EvZ]
    /\ rollbackAuthorized' = [x \in Server |-> x = Node]
    /\ UNCHANGED <<serverVars, queued, appended, durable, snapshot, acked,
                    commitCertified, messages, syncVars, usedTxn,
                    maxCommitted, ackedHist>>
    /\ LastLoggedNext(Node) = EvZ

\* PROPOSAL during sync -> packetsNotCommitted.add (Learner.java:621-641).
SyncProposalBufferedStep ==
    /\ EventName = "SyncProposalBuffered"
    /\ role[Node] = "following" /\ learnerStep[Node] \in {"synced", "acked"}
    /\ HasEntry(proposed[leaderOf[Node]], TxnEntry)
    /\ proposed' = [proposed EXCEPT ![Node] = Append(@, TxnEntry)]
    /\ pending' = [pending EXCEPT ![Node] = Append(@, TxnEntry)]
    /\ Len(pending'[Node]) = Aux.pending
    /\ Len(syncCommits[Node]) = Aux.committed
    /\ UNCHANGED <<serverVars, queued, appended, durable, committed, applied,
                    snapshot, acked, commitCertified, messages, syncMode,
                    syncSource, syncJustified, syncCommits, zkState,
                    learnerStep, nlAcks, usedTxn, rollbackAuthorized,
                    maxCommitted, ackedHist, treeFloor>>

\* COMMIT during sync with writeToTxnLog -> packetsCommitted.add (:666-667).
SyncCommitBufferedStep ==
    /\ EventName = "SyncCommitBuffered"
    /\ role[Node] = "following" /\ learnerStep[Node] \in {"synced", "acked"}
    /\ syncMode[Node] = "DIFF" \/ learnerStep[Node] = "acked"
    /\ LET k == Len(committed[Node]) + Len(syncCommits[Node]) + 1 IN
       /\ k <= Len(proposed[Node]) /\ proposed[Node][k] = TxnEntry
    /\ syncCommits' = [syncCommits EXCEPT ![Node] = Append(@, TxnEntry)]
    /\ commitCertified' = [commitCertified EXCEPT ![TxnEntry.id] = TRUE]
    /\ Len(syncCommits'[Node]) = Aux.committed
    /\ Len(pending[Node]) = Aux.pending
    /\ UNCHANGED <<serverVars, logVars, acked, messages, syncMode, syncSource,
                    syncJustified, pending, zkState, learnerStep, nlAcks,
                    usedTxn, rollbackAuthorized, maxCommitted, ackedHist,
                    treeFloor>>

\* COMMIT before NEWLEADER without txn log: processTxn (:653-665).
SyncCommitAppliedStep ==
    /\ EventName = "SyncCommitApplied"
    /\ learnerStep[Node] = "synced" /\ syncMode[Node] /= "DIFF"
    /\ pending[Node] /= <<>> /\ Head(pending[Node]) = TxnEntry
    /\ applied' = [applied EXCEPT ![Node] = Append(@, TxnEntry)]
    /\ committed' = [committed EXCEPT ![Node] = Append(@, TxnEntry)]
    /\ pending' = [pending EXCEPT ![Node] = Tail(@)]
    /\ commitCertified' = [commitCertified EXCEPT ![TxnEntry.id] = TRUE]
    /\ UNCHANGED <<serverVars, proposed, queued, appended, durable, snapshot,
                    acked, messages, syncMode, syncSource, syncJustified,
                    syncCommits, zkState, learnerStep, nlAcks, usedTxn,
                    rollbackAuthorized, maxCommitted, ackedHist, treeFloor>>

-----------------------------------------------------------------------------
(* Update window: base actions *)

\* Implied Leader.propose of the current event's entry at leader ld: only
\* the leader's next zxid of its current epoch, while it is serving.
ProposeImplied(ld) ==
    /\ ld \in Server /\ role[ld] = "leading" /\ zkState[ld] = "RUNNING"
    /\ TxnEntry.epoch = currentEpoch[ld]
    /\ TxnEntry.ctr = NextCtr(proposed[ld], currentEpoch[ld])
    /\ TxnEntry.id \notin usedTxn

ProposalQueuedStep ==
    /\ EventName = "ProposalQueued"
    /\ \/ /\ learnerStep[Node] = "started"
          /\ LearnerLogPendingOne(Node)                    \* NEWLEADER part 3
       \/ /\ learnerStep[Node] = "serving"
          /\ LearnerUptodateLogOne(Node)
       \/ /\ role[Node] = "following" /\ phase[Node] = "broadcast"
          /\ zkState[Node] = "RUNNING" /\ learnerStep[Node] = "none"
          \* Follower.processPacket PROPOSAL -> logRequest (ReceiveProposal)
          /\ LET ld == leaderOf[Node]
                 \* Leader.propose is not instrumented: the follower may log
                 \* the PROPOSAL before the leader's own append is traced.
                 implied == /\ Len(proposed[Node]) = Len(proposed[ld])
                            /\ ProposeImplied(ld)
                 lp == IF implied THEN Append(proposed[ld], TxnEntry)
                       ELSE proposed[ld] IN
             /\ Len(proposed[Node]) < Len(lp)
             /\ lp[Len(proposed[Node]) + 1] = TxnEntry
             /\ proposed' = [proposed EXCEPT ![Node] = Append(@, TxnEntry),
                                             ![ld] = lp]
             /\ queued' = [queued EXCEPT ![Node] = Append(@, TxnEntry),
                                         ![ld] = IF implied THEN Append(@, TxnEntry)
                                                 ELSE @]
             /\ usedTxn' = IF implied THEN usedTxn \cup {TxnEntry.id} ELSE usedTxn
          /\ UNCHANGED <<serverVars, appended, durable, committed, applied,
                          snapshot, acked, commitCertified, messages, syncVars,
                          rollbackAuthorized, maxCommitted, ackedHist,
                          treeFloor>>
    /\ Last(queued'[Node]) = TxnEntry

\* The probe runs after writePacket(ACK), so the leader may log its receipt
\* first; NewLeaderAckCountedStep then performs LearnerSendNewLeaderAck for
\* the learner and this event only validates the learner's fields.
NewLeaderAckSentStep ==
    /\ EventName = "NewLeaderAckSent"
    /\ \/ LearnerSendNewLeaderAck(Node)                    \* NEWLEADER part 4
       \/ /\ learnerStep[Node] = "acked"
          /\ leaderOf[Node] \in Server /\ Node \in nlAcks[leaderOf[Node]]
          /\ UNCHANGED allVars
    /\ EvZ = Zx(acceptedEpoch[Node], 0)
    /\ Aux.pending = Len(pending'[Node])
    /\ Aux.committed = Len(syncCommits'[Node])
    /\ ZkMap(Aux.zkState) = zkState'[Node]

UptodateReceivedStep ==
    /\ EventName = "UptodateReceived"
    /\ learnerStep[Node] = "acked"
    /\ Aux.pending = Len(pending[Node])
    /\ Aux.committed = Len(syncCommits[Node])
    /\ ZkMap(Aux.zkState) = zkState[Node]
    /\ UNCHANGED allVars

ZkServerStateStep ==
    /\ EventName = "ZkServerState"
    /\ CASE Aux.zkState = "INITIAL" ->
              /\ learnerStep[Node] = "started" /\ zkState[Node] = "INITIAL"
              /\ UNCHANGED allVars
         [] Aux.zkState = "RUNNING" /\ role[Node] = "following" ->
              /\ LearnerUptodateStartServing(Node)
         [] Aux.zkState = "RUNNING" /\ role[Node] = "leading" ->
              /\ LastLogged(Node) = EvZ
              /\ LeaderStartZkServer(Node)
         [] Aux.zkState \in {"SHUTDOWN", "ERROR"} ->
              UNCHANGED allVars
         [] OTHER -> FALSE

BroadcastReadyStep ==
    /\ EventName = "BroadcastReady"
    /\ learnerStep[Node] = "serving" /\ zkState[Node] = "RUNNING"
    /\ LastLogged(Node) = EvZ
    /\ Aux.pending = Len(pending[Node])
    /\ Aux.committed = Len(syncCommits[Node])
    /\ UNCHANGED allVars

\* Leader commit is not instrumented: when a COMMIT or leader apply is
\* observed, the leader must already have the proposal and a quorum of
\* servers must have fsynced it (Leader.tryToCommit, ACK after flush).
LeaderCommitted(ld, e) ==
    IF HasEntry(committed[ld], e) THEN committed[ld]
    ELSE PrefixThrough(proposed[ld], e)
LeaderCommitOK(ld, e) ==
    /\ HasEntry(proposed[ld], e)
    /\ HasEntry(committed[ld], e)
       \/ Cardinality({s \in Server : HasEntry(durable[s], e)}) >= Quorum

CommitDeliveredStep ==
    /\ EventName = "CommitDelivered"
    /\ \/ /\ learnerStep[Node] = "serving"
          /\ LearnerUptodateCommitOne(Node)
       \/ /\ role[Node] = "following" /\ phase[Node] = "broadcast"
          /\ learnerStep[Node] = "none" /\ zkState[Node] = "RUNNING"
          /\ LET ld == leaderOf[Node] IN
             /\ LeaderCommitOK(ld, TxnEntry)
             /\ Len(committed[Node]) < Len(proposed[Node])
             /\ proposed[Node][Len(committed[Node]) + 1] = TxnEntry
             /\ committed' = [committed EXCEPT ![Node] = Append(@, TxnEntry),
                                               ![ld] = LeaderCommitted(ld, TxnEntry)]
             /\ commitCertified' = [commitCertified EXCEPT ![TxnEntry.id] = TRUE]
             /\ maxCommitted' = GrowGhost(maxCommitted, LeaderCommitted(ld, TxnEntry))
          /\ UNCHANGED <<serverVars, proposed, queued, appended, durable,
                          applied, snapshot, acked, messages, syncVars, usedTxn,
                          rollbackAuthorized, ackedHist, treeFloor>>
    /\ Last(committed'[Node]) = TxnEntry

TxnAppendedStep ==
    /\ EventName = "TxnAppended"
    /\ \/ /\ Len(appended[Node]) < Len(queued[Node])
          /\ queued[Node][Len(appended[Node]) + 1] = TxnEntry
          /\ AppendOne(Node)
       \/ /\ Len(appended[Node]) = Len(queued[Node])
          \* Leader.propose (not instrumented) then the local append.
          /\ ProposeImplied(Node)
          /\ proposed' = [proposed EXCEPT ![Node] = Append(@, TxnEntry)]
          /\ queued' = [queued EXCEPT ![Node] = Append(@, TxnEntry)]
          /\ appended' = [appended EXCEPT ![Node] = Append(@, TxnEntry)]
          /\ usedTxn' = usedTxn \cup {TxnEntry.id}
          /\ UNCHANGED <<serverVars, durable, committed, applied, snapshot,
                          acked, commitCertified, messages, syncVars,
                          rollbackAuthorized, maxCommitted, ackedHist,
                          treeFloor>>
    /\ Last(appended'[Node]) = TxnEntry

TxnDurableStep ==
    /\ EventName = "TxnDurable"
    /\ \/ /\ Len(durable[Node]) < Len(appended[Node])
          /\ appended[Node][Len(durable[Node]) + 1] = TxnEntry
          /\ FsyncOne(Node)
       \/ /\ HasEntry(durable[Node], TxnEntry)   \* drained by shutdown
          /\ UNCHANGED allVars
    /\ HasEntry(durable'[Node], TxnEntry)

TxnAppliedStep ==
    /\ EventName = "TxnApplied"
    /\ zkState[Node] = "RUNNING"
    /\ \/ /\ HasEntry(committed[Node], TxnEntry)
          /\ ApplyOne(Node)
       \/ /\ role[Node] = "leading" /\ ~HasEntry(committed[Node], TxnEntry)
          /\ LeaderCommitOK(Node, TxnEntry)
          /\ LET c == LeaderCommitted(Node, TxnEntry) IN
             /\ IsPrefix(applied[Node], c)
             /\ Len(applied[Node]) + 1 = Len(c)
             /\ committed' = [committed EXCEPT ![Node] = c]
             /\ applied' = [applied EXCEPT ![Node] = c]
             /\ commitCertified' = [commitCertified EXCEPT ![TxnEntry.id] = TRUE]
             /\ maxCommitted' = GrowGhost(maxCommitted, c)
          /\ UNCHANGED <<serverVars, proposed, queued, appended, durable,
                          snapshot, acked, messages, syncVars, usedTxn,
                          rollbackAuthorized, ackedHist, treeFloor>>
    /\ Last(applied'[Node]) = TxnEntry

\* Learner/ZooKeeperServer.shutdown (canShutdown guard) -> ServerShutdown.
ShutdownStep ==
    /\ \/ /\ EventName = "ZkShutdownSkipped" /\ Aux.zkState = "INITIAL"
          /\ role[Node] \in {"leading", "following"}
          /\ zkState[Node] /= "RUNNING"
          /\ LastLogged(Node) = EvZ
          /\ LogMatches(Node, LogZ)
          /\ ServerShutdown(Node)
          /\ UNCHANGED treeFloor
       \/ /\ EventName = "ZkShutdownStarted"
          /\ role[Node] \in {"leading", "following"}
          /\ zkState[Node] = "RUNNING" /\ Aux.zkState = "RUNNING"
          /\ LastLogged(Node) = EvZ
          /\ LogMatches(Node, LogZ)
          /\ ServerShutdown(Node)
          /\ UNCHANGED treeFloor
       \/ /\ EventName = "ZkShutdownSkipped"
          /\ (Aux.zkState = "SHUTDOWN" \/ role[Node] = "looking")
          /\ UNCHANGED allVars

ShutdownObserveStep ==
    /\ EventName \in {"ZkTreeFastForwarded", "ZkSyncDrained"}
    /\ role[Node] = "looking"
    /\ EventName = "ZkTreeFastForwarded" => LastLogged(Node) = EvZ
    /\ LogMatches(Node, LogZ)
    /\ UNCHANGED allVars

NewLeaderAckCountedStep ==
    /\ EventName = "NewLeaderAckCounted"
    /\ role[Node] = "leading"
    /\ EvZ = Zx(acceptedEpoch[Node], 0)
    /\ LET p == Aux.peer IN
       /\ p \in Server
       /\ \/ /\ p = Node \/ p \in nlAcks[Node]
             /\ nlAcks' = [nlAcks EXCEPT ![Node] = @ \cup {p}]
             /\ UNCHANGED <<serverVars, logVars, acked, commitCertified,
                             messages, syncMode, syncSource, syncJustified,
                             pending, syncCommits, zkState, learnerStep,
                             usedTxn, rollbackAuthorized, maxCommitted,
                             ackedHist, treeFloor>>
          \/ /\ p /= Node /\ p \notin nlAcks[Node]
             /\ leaderOf[p] = Node /\ learnerStep[p] = "started"
             /\ LearnerSendNewLeaderAck(p)    \* ACK written before its probe

NewLeaderAckRejectedStep ==
    /\ EventName = "NewLeaderAckRejected"
    /\ role[Node] = "leading" /\ Aux.peer \in Server
    /\ EvZ /= Zx(acceptedEpoch[Node], 0)
    /\ UNCHANGED allVars

NewLeaderQuorumStep ==
    /\ EventName = "NewLeaderQuorum"
    /\ role[Node] = "leading" /\ phase[Node] = "sync"
    /\ Cardinality(nlAcks[Node] \cup {Node}) >= Quorum
    /\ LogMatches(Node, LogZ)
    /\ UNCHANGED allVars

-----------------------------------------------------------------------------
TraceStep ==
    \/ DatabaseLoadedStep
    \/ PeerRoleStep
    \/ PhaseStep
    \/ AcceptedEpochStep
    \/ CurrentEpochStep
    \/ FollowerRegisteredStep
    \/ SyncModeStep
    \/ SyncSelectedStep
    \/ SnapshotInstalledStep
    \/ SyncProposalBufferedStep
    \/ SyncCommitBufferedStep
    \/ SyncCommitAppliedStep
    \/ ProposalQueuedStep
    \/ NewLeaderAckSentStep
    \/ UptodateReceivedStep
    \/ ZkServerStateStep
    \/ BroadcastReadyStep
    \/ CommitDeliveredStep
    \/ TxnAppendedStep
    \/ TxnDurableStep
    \/ TxnAppliedStep
    \/ ShutdownStep
    \/ ShutdownObserveStep
    \/ NewLeaderAckCountedStep
    \/ NewLeaderAckRejectedStep
    \/ NewLeaderQuorumStep

TraceNext ==
    /\ l <= Len(TraceLog)
    /\ TraceStep
    /\ IF EventName = "ZkServerState" /\ Aux.zkState \in {"SHUTDOWN", "ERROR"}
       THEN ValidateShutdownStatePost
       ELSE ValidateCommonPostState
    /\ l' = l + 1

-----------------------------------------------------------------------------
E(ep, c) == [id |-> TxnIdOf(ep, c), epoch |-> ep, ctr |-> c]
\* The DIFF conversation anchors its DIFF at 1.1 but talks to an empty
\* follower and streams only PROPOSAL/COMMIT 1.2 (Zab1_0Test.java:751-768);
\* the scripted leader's history is exactly what it streams.
FixtureHist == IF TraceScenario = "follower-diff" THEN <<E(1, 2)>>
               ELSE <<E(1, 1), E(1, 1000)>>
FixtureTree == IF TraceScenario = "follower-diff" THEN <<E(1, 2)>>
               ELSE <<E(1, 1)>>

\* Zab1_0Test scripts an established epoch-1 leader (Zab1_0Test.java
\* testNormalFollowerRun / testNormalFollowerRunWithDiff): its history is the
\* scripted proposals; the follower under test starts empty.
TraceInit ==
    /\ l = 1
    /\ IF Fixture
       THEN /\ up = [s \in Server |-> TRUE]
            /\ role = [s \in Server |-> CASE s = FixLeader -> "leading"
                                          [] s = FixFollower -> "following"
                                          [] OTHER -> "looking"]
            /\ phase = [s \in Server |-> CASE s = FixLeader -> "broadcast"
                                           [] OTHER -> "election"]
            /\ leaderOf = [s \in Server |-> IF s \in {FixLeader, FixFollower}
                                            THEN FixLeader ELSE Nil]
            /\ acceptedEpoch = [s \in Server |-> IF s = FixLeader THEN 1 ELSE 0]
            /\ currentEpoch = [s \in Server |-> IF s = FixLeader THEN 1 ELSE 0]
            /\ votes = [s \in Server |-> {}]
            /\ leadersByEpoch = [e \in Epoch |-> IF e = 1 THEN {FixLeader} ELSE {}]
            /\ proposed = [s \in Server |-> IF s = FixLeader THEN FixtureHist ELSE <<>>]
            /\ queued = [s \in Server |-> IF s = FixLeader THEN FixtureHist ELSE <<>>]
            /\ appended = [s \in Server |-> IF s = FixLeader THEN FixtureHist ELSE <<>>]
            /\ durable = [s \in Server |-> IF s = FixLeader THEN FixtureHist ELSE <<>>]
            /\ committed = [s \in Server |-> IF s = FixLeader THEN FixtureHist ELSE <<>>]
            /\ applied = [s \in Server |-> IF s = FixLeader THEN FixtureTree ELSE <<>>]
            /\ snapshot = [s \in Server |-> <<>>]
            /\ acked = [t \in Txn |-> {}]
            /\ commitCertified = [t \in Txn |-> t \in TxnIds(FixtureHist)]
            /\ messages = {}
            /\ syncMode = [s \in Server |-> "NONE"]
            /\ syncSource = [s \in Server |-> Nil]
            /\ syncJustified = [s \in Server |-> FALSE]
            /\ pending = [s \in Server |-> <<>>]
            /\ syncCommits = [s \in Server |-> <<>>]
            /\ zkState = [s \in Server |-> IF s = FixLeader THEN "RUNNING" ELSE "OFF"]
            /\ learnerStep = [s \in Server |-> "none"]
            /\ nlAcks = [s \in Server |-> {}]
            /\ usedTxn = TxnIds(FixtureHist)
            /\ rollbackAuthorized = [s \in Server |-> FALSE]
            /\ maxCommitted = FixtureHist
            /\ ackedHist = [s \in Server |-> <<>>]
            /\ treeFloor = [s \in Server |-> IF s = FixLeader THEN Zx(1, 0) ELSE NoZxid]
       ELSE Init

TraceSpec == TraceInit /\ [][TraceNext]_<<allVars, traceVars>>
                       /\ WF_<<allVars, traceVars>>(TraceNext)

TraceMatched == <>(l > Len(TraceLog))

\* Diagnostic for debugging only.
TraceAlias == [l |-> l, ev |-> IF l <= Len(TraceLog) THEN EventName ELSE "done",
               node |-> IF l <= Len(TraceLog) THEN Node ELSE "-"]

=============================================================================
